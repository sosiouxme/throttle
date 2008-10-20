require File.dirname(__FILE__) + '/spec_helper.rb'

describe "a throttle" do
  it "should keep the totals spanning multiple buckets" do
    t = Throttle.new(:buckets => 5, :time_per_bucket => 1)
    def t.test_threshold(count)
      raise 'bork' if count > 2
    end
    lambda { t.record_event }.should_not raise_error('bork')
    sleep(1)
    lambda { t.record_event }.should_not raise_error('bork')
    sleep(1)
    lambda { t.record_event }.should raise_error('bork')
  end

  it "should not include expired buckets in the count" do
    t = Throttle.new(:buckets => 2, :time_per_bucket => 1)
    def t.test_threshold(count)
      raise 'bork' if count > 2
    end
    lambda { t.record_event }.should_not raise_error('bork')
    sleep(1)
    lambda { t.record_event }.should_not raise_error('bork')
    sleep(1)
    lambda { t.record_event }.should_not raise_error('bork')
  end

  it "should not break if the throttle expires while we wait" do
    t = Throttle.new(:buckets => 2, :time_per_bucket => 1)
    def t.test_threshold(count)
      raise 'bork' if count > 2
    end
    t.record_event
    sleep(2)
    t.record_event #}.should_not raise_error()
  end

  it "should be created, then found in the cache" do
    t = Throttle.new(:name => 'foo')
    sleep(2)
    t2 = Throttle.new(:name => 'foo')
    t2.initial_time.should == t.initial_time
  end

end
