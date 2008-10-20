class Throttle
  # the memcached object instance we'll be using
  @@memcache = nil
  def Throttle.set_memcache(cache)
    @@memcache = cache
  end

  # the namespace prefix all throttles will use in the cache
  CACHE_PREFIX = 'Throttle:'

  attr_reader :name, :buckets, :time_per_bucket, :initial_time

  # retrieve, or else create a new one; always update expiration
  def Throttle.create(args = {})
    throttle = self.retrieve(args[:name] || '')
    unless throttle
      throttle = self.new(args)
    end
    throttle.store
  end

  ############################################################
  # This method must be overridden!
  #
  # the action that is taken at a threshold must be specified
  # in a subclass or singleton method. why not a block or
  # callback? because that would have to be stored with the
  # object, and the object must be serializable for memcache.

  def test_threshold(count) #abstract!
  # this is called whenever an event occurs and passed
  # the new tally so that action may be taken if needed.
    raise '#test_threshold must be defined in a subclass'
  end


  ####################################################
  # use the throttle
  def record_event
    bucket = current_bucket()
    begin
      if new_val = @@memcache.incr(gen_bucket_key(bucket))
        prev_sum = @@memcache.get(gen_summary_key(bucket)) || 0;
        test_threshold(total = sum_prevsum_and_bucket(prev_sum, new_val))
        return total
      else
      # the bucket must not exist yet. create it.
      # herein lies the only race condition i know of -
      # if two create a bucket at the same time, one of
      # the events won't be counted. i think that's acceptable.
        prev_sum = create_bucket(bucket)
        test_threshold(total = sum_prevsum_and_bucket(prev_sum, 1))
        return total
      end
    rescue MemCache::MemCacheError
      return nil #memcache not working, ignore throttle
    end
  end

  #########################################################
  # try to have the class find an existing throttle
  # (so we know whether to use previous or create it)

  # have this throttle object store itself into the memcache;
  # it will expire if new buckets are not created
  def store
    begin
      @@memcache.set(self.gen_throttle_key, self,
        Time.now.to_i + @buckets * @time_per_bucket)
    rescue MemCache::MemCacheError
      #memcache not working, silently ignore
    end
    return self
  end

  def Throttle.retrieve(name)
    begin
      t = @@memcache.get( self.gen_throttle_key(name) )
      return t if t
      # if there isn't one... there's just no throttle.
      return nil
    rescue MemCache::MemCacheError
      return nil #memcache not working, ignore throttle
    end
  end

  def initialize(args = {})
    # expecting args:
    # :name -> uniquely identifying throttle name
    # :buckets -> number of buckets to track
    # :time_per_bucket -> seconds during which each bucket counts
    # number => Proc -> procedure to run when number threshold hit
    @name = args.delete(:name) || ""
    @buckets = args.delete(:buckets) || 1
    @time_per_bucket = args.delete(:time_per_bucket) || 60

    # intialize some stuff
    @initial_time ||= Time.now.to_i
  end

protected

  ##########################################
  # some functions to determine cache keys
  def Throttle.gen_throttle_key(name)
    CACHE_PREFIX + 'obj:' + name
  end
  def gen_throttle_key
    self.class.gen_throttle_key(@name)
  end
  def gen_bucket_key(bucket)
    CACHE_PREFIX + 'bkt:' + @name + ':' + bucket.to_s
  end
  def gen_summary_key(bucket)
    CACHE_PREFIX + 'sum:' + @name + ':' + bucket.to_s
  end

  # in order to keep a running tally of recent events, the
  # time period is broken up into multiple buckets which are
  # tallied separately and summed to get the full count. so
  # for instance, an hour may be broken up into 10 buckets
  # each covering 6 minutes. the most recent 10 buckets are
  # added for the full hour's tally; older buckets are
  # discarded after an hour.
  #
  # in order to do the sum without constantly accessing lots
  # of bucket entries, previous buckets (which don't change
  # anyway) should be summed when a new bucket is created.
  # this is the "summarize_previous_buckets" method.
  #
  # then at the time an event is tallied, only the previous
  # sum and the current bucket need to be combined (via the
  # "sum_prevsum_and_bucket" method) for the full tally.
  #
  # a simple "summarizing" scheme would be to just add all of
  # the buckets together. more complex schemes might use
  # weighted sums to give more recent events higher weight
  # or something.

  def summarize_previous_buckets(array)
    sum = 0
    print array.inspect
    array.each { |n| sum += n }
    return sum
  end
  def sum_prevsum_and_bucket(prev_sum, current)
    return prev_sum + current
  end

  def current_bucket
    return (Time.now.to_i - @initial_time) / @time_per_bucket
  end

  # get the buckets prior to this one so can summarize them
  def get_previous_buckets(bucket)
    prev_buckets = Range.new(bucket-@buckets+1, bucket-1).to_a
    prev_buckets.reject!{|n| n < 0} #won't exist before 0
    prev_buckets.map!{|n| gen_bucket_key(n)} #map to cache keys
    if !prev_buckets.empty?
      prev_buckets = [*@@memcache.get(*prev_buckets)]
    end
    prev_buckets.map!{|n| n ||= 0}  #fill w/ 0 if any are missing
    return prev_buckets
  end

  def create_bucket(bucket)
    self.store # renew throttle expiration time
    expiry = (bucket + @buckets) * @time_per_bucket
    @@memcache.set(gen_bucket_key(bucket), 1, expiry)

    # we need to set up the summary from previous buckets
    prev_sum = summarize_previous_buckets(get_previous_buckets(bucket))
    @@memcache.set(gen_summary_key(bucket), prev_sum, expiry);
    return prev_sum
  end

end # class
