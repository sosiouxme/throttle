class Throttle

  # the memcached object instance we'll be using
  @@memcache = nil
  def Throttle.memcache=(cache) @@memcache = cache end
  def Throttle.memcache() @@memcache end

  # the namespace prefix for all throttles in the cache
  @@prefix = 'Throttle:'
  def Throttle.prefix=(str) @@prefix = str end
  def Throttle.prefix() @@prefix end


  attr_reader :name, :intervals, :interval_secs, :initial_time

  def initialize(name = '', args = {}, &test)
    # expecting args:
    # :name -> uniquely identifying throttle name
    # :intervals -> number of intervals to track
    # :interval_secs -> seconds during which each interval counts
    # number => Proc -> procedure to run when number threshold hit
    @name = name
    @intervals = args.delete(:intervals) || 1
    @interval_secs = args.delete(:interval_secs) || 60
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
    interval = current_interval()
    begin
      prev_sum = 0
      new_val = @@memcache.incr(gen_interval_key(interval), count)
      if new_val
        prev_sum = @@memcache.get(gen_summary_key(interval)) || 0;
      else # the interval must not exist yet. create.
        prev_sum = create_interval(interval)
        new_val = @@memcache.incr(gen_interval_key(interval), count)
      end
      test_threshold(total = sum_prevsum_and_interval(prev_sum, new_val))
      return total
    rescue MemCache::MemCacheError
      return nil #memcache not working, ignore throttle
    end
  end
  alias :incr :record_event

protected

  ############################################################
  # in order to keep a running tally of recent events, the
  # time period is broken up into multiple intervals which are
  # tallied separately and summed to get the full count. so
  # for instance, an hour may be broken up into 10 intervals
  # each covering 6 minutes. the most recent 10 intervals are
  # added for the full hour's tally; older intervals are
  # discarded after an hour.
  #
  # in order to do the sum without constantly accessing lots
  # of interval entries, previous intervals (which don't change
  # anyway) should be summed when a new interval is created.
  # this is the "summarize_previous_intervals" method.
  #
  # then at the time an event is tallied, only the previous
  # sum and the current interval need to be combined (via the
  # "sum_prevsum_and_interval" method) for the full tally.
  #
  # a simple "summarizing" scheme would be to just add all of
  # the intervals together. more complex schemes might use
  # weighted sums to give more recent events higher weight
  # or something.

  def summarize_previous_intervals(array)
    array.inject(0) { |sum,n| sum += n }
  end
  def sum_prevsum_and_interval(prev_sum, current)
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
  # memcache; it will expire if new intervals are not created
  def store_time
    begin
      @@memcache.set(self.gen_throttle_key, @initial_time,
        Time.now.to_i + @intervals * @interval_secs)
    rescue MemCache::MemCacheError
      #memcache not working, silently ignore
    end
    return self
  end

  ##########################################
  # some functions to determine cache keys
  def gen_throttle_key
    @@prefix + 'exp:' + @name
  end
  def gen_interval_key(interval)
    @@prefix + 'bkt:' + @name + ':' + interval.to_s
  end
  def gen_summary_key(interval)
    @@prefix + 'sum:' + @name + ':' + interval.to_s
  end

  def current_interval
    return (Time.now.to_i - @initial_time) / @interval_secs
  end

  # get the intervals prior to this one so can summarize them
  def get_previous_intervals(interval)
    prev_intervals = Range.new(interval-@intervals+1, interval-1).to_a
    prev_intervals.reject!{|n| n < 0} #won't exist before 0
    prev_intervals.map!{|n| gen_interval_key(n)} #map to cache keys
    if !prev_intervals.empty?
      prev_intervals = [*@@memcache.get(*prev_intervals)]
      prev_intervals.map!{|n| n || 0}  #fill w/ 0 if any are missing
    end
    return prev_intervals
  end

  def create_interval(interval)
    self.store_time # renew throttle expiration time
    expiry = (interval + @intervals) * @interval_secs
    #
    # we need to set up the summary from previous intervals
    prev_sum = summarize_previous_intervals(get_previous_intervals(interval))
    if !@@memcache.add(gen_summary_key(interval), prev_sum, expiry)
      # in a race, another process might store a different summary first;
      # in that case, use whatever it came up with
      prev_sum = @@memcache.get(gen_summary_key(interval)) || prev_sum
    end

    # "add" interval - this will fail silently in a race
    @@memcache.add(gen_interval_key(interval), 0, expiry)
    return prev_sum
  end

end # class
