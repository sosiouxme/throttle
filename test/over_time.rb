require File.dirname(__FILE__) + '/spec_helper.rb'

describe "a throttle" do

  it "should be created, then found in the cache" do
    t = Throttle.new(:name => 'foo')
    sleep(2)
    t2 = Throttle.new(:name => 'foo')
    t2.initial_time.should == t.initial_time
  end

  it "should keep the totals spanning multiple buckets" do
    t = Throttle.new(:buckets => 5, :time_per_bucket => 1) {|count| raise 'bork' if count > 2 }
    lambda { t.record_event }.should_not raise_error('bork')
    sleep(1)
    lambda { t.record_event }.should_not raise_error('bork')
    sleep(1)
    lambda { t.record_event }.should raise_error('bork')
  end

  it "should not include expired buckets in the count" do
    t = Throttle.new(:buckets => 2, :time_per_bucket => 1) {|count| raise 'bork' if count > 2 }
    lambda { t.record_event }.should_not raise_error('bork')
    sleep(1)
    lambda { t.record_event }.should_not raise_error('bork')
    sleep(1)
    lambda { t.record_event }.should_not raise_error('bork')
  end

  it "should not break if the throttle expires while we wait" do
    t = Throttle.new(:buckets => 2, :time_per_bucket => 1) {|count| raise 'bork' if count > 2 }
    t.record_event
    sleep(2)
    lambda { t.record_event }.should_not raise_error()
  end

  it "should lose a bucket creation race gracefully" do
    t = Throttle.new(:buckets => 2, :time_per_bucket => 1) {|count| raise 'bork' if count > 10 }
    t.record_event
    sleep(1)
    @cache['Throttle:sum::1'] = 9 # simulate prev. sum created
    # but since there's no bucket, it will try to create one.
    # setting the sum will fail and use the one supplied,
    # but the bucket entry will be added normally.
    lambda { t.record_event }.should_not raise_error('bork')
    lambda { t.record_event }.should raise_error('bork')
  end

end
