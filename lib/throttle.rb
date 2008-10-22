class Throttle
  # the memcached object instance we'll be using
  @@memcache = nil
  def Throttle.memcache=(cache)
    @@memcache = cache
  end
  def Throttle.memcache(cache)
    @@memcache
  end

  # the namespace prefix for all throttles in the cache
  CACHE_PREFIX = 'Throttle:'

  attr_reader :name, :buckets, :time_per_bucket, :initial_time

  def initialize(args = {}, &test)
    # expecting args:
    # :name -> uniquely identifying throttle name
    # :buckets -> number of buckets to track
    # :time_per_bucket -> seconds during which each bucket counts
    # number => Proc -> procedure to run when number threshold hit
    @name = args.delete(:name) || ""
    @buckets = args.delete(:buckets) || 1
    @time_per_bucket = args.delete(:time_per_bucket) || 60
    args[:always] = test if test
    @test = args

    # intialize start time
    self.retrieve_time #gets start time of existing throttle if any
    @initial_time ||= Time.now.to_i
    self.store_time #update expiration
  end

  ####################################################
  # use the throttle
  def record_event(count = 1)
    bucket = current_bucket()
    begin
      prev_sum = 0
      new_val = @@memcache.incr(gen_bucket_key(bucket), count)
      if new_val
        prev_sum = @@memcache.get(gen_summary_key(bucket)) || 0;
      else # the bucket must not exist yet. create.
        prev_sum = create_bucket(bucket)
        new_val = @@memcache.incr(gen_bucket_key(bucket), count)
      end
      test_threshold(total = sum_prevsum_and_bucket(prev_sum, new_val))
      return total
    rescue MemCache::MemCacheError
      return nil #memcache not working, ignore throttle
    end
  end

protected

  ############################################################
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
    array.inject(0) { |sum,n| sum += n }
  end
  def sum_prevsum_and_bucket(prev_sum, current)
    return prev_sum + current
  end


  ############################################################
  # as written the test_threshold method expects a block or
  # callback(s) to be supplied at instantiation time.

  def test_threshold(count)
  # this is called whenever an event occurs and is passed
  # the new tally so that action may be taken if needed.
  # if multiple callbacks apply they run in unspecified order.
    @test.each do |k,callback|
      next unless callback.is_a? Proc
      if k.is_a? Range
        next unless k.include? count
      elsif k.is_a? Fixnum
        next unless k == count
      elsif k == :always
        # always run callback
      else
        next # unknown stuff in hash
      end
      if callback.arity == 1
        callback.call(count)
      else
        callback.call(count,self)
      end
    end
  end

  #########################################################
  # try to have the class find an existing throttle
  # (so we know whether to use previous timestamp)

  def retrieve_time
    begin
      @initial_time = @@memcache.get( gen_throttle_key() ) || @initial_time
    rescue MemCache::MemCacheError
      #memcache not working, silently ignore
    end
  end

  # have this throttle object store its time into the
  # memcache; it will expire if new buckets are not created
  def store_time
    begin
      @@memcache.set(self.gen_throttle_key, @initial_time,
        Time.now.to_i + @buckets * @time_per_bucket)
    rescue MemCache::MemCacheError
      #memcache not working, silently ignore
    end
    return self
  end

  ##########################################
  # some functions to determine cache keys
  def gen_throttle_key
    CACHE_PREFIX + 'exp:' + name
  end
  def gen_bucket_key(bucket)
    CACHE_PREFIX + 'bkt:' + @name + ':' + bucket.to_s
  end
  def gen_summary_key(bucket)
    CACHE_PREFIX + 'sum:' + @name + ':' + bucket.to_s
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
      prev_buckets.map!{|n| n || 0}  #fill w/ 0 if any are missing
    end
    return prev_buckets
  end

  def create_bucket(bucket)
    self.store_time # renew throttle expiration time
    expiry = (bucket + @buckets) * @time_per_bucket
    #
    # we need to set up the summary from previous buckets
    prev_sum = summarize_previous_buckets(get_previous_buckets(bucket))
    if !@@memcache.add(gen_summary_key(bucket), prev_sum, expiry)
      # in a race, another process might store a different summary first;
      # in that case, use whatever it came up with
      prev_sum = @@memcache.get(gen_summary_key(bucket)) || prev_sum
    end

    # "add" bucket - this will fail silently in a race
    @@memcache.add(gen_bucket_key(bucket), 0, expiry)
    return prev_sum
  end

end # class
