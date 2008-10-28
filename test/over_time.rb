require File.dirname(__FILE__) + '/spec_helper.rb'

describe "a throttle" do

  it "should be created, then found in the cache" do
    t = Throttle.new('foo')
    sleep(2)
    t2 = Throttle.new('foo')
    t2.initial_time.should == t.initial_time
  end

  it "should keep the totals spanning multiple intervals" do
    t = Throttle.new('', :intervals => 5, :interval_secs => 1) {|count| raise 'bork' if count > 2 }
    lambda { t.record_event }.should_not raise_error('bork')
    sleep(1)
    lambda { t.record_event }.should_not raise_error('bork')
    sleep(1)
    lambda { t.record_event }.should raise_error('bork')
  end

  it "should not include expired intervals in the count" do
    t = Throttle.new('', :intervals => 2, :interval_secs => 1) {|count| raise 'bork' if count > 2 }
    lambda { t.record_event }.should_not raise_error('bork')
    sleep(1)
    lambda { t.record_event }.should_not raise_error('bork')
    sleep(1)
    lambda { t.record_event }.should_not raise_error('bork')
  end

  it "should not break if the throttle expires while we wait" do
    t = Throttle.new('', :intervals => 2, :interval_secs => 1) {|count| raise 'bork' if count > 2 }
    t.record_event
    sleep(2)
    lambda { t.record_event }.should_not raise_error()
  end

  #TODO: find out why this fails with the real memcache
  it "should lose a interval creation race gracefully" do
    t = Throttle.new('', :intervals => 2, :interval_secs => 1) {|count| raise 'bork' if count > 10 }
    t.record_event
    sleep(1)
    @cache['Throttle:sum::1'] = 9 # simulate prev. sum created
    # but since there's no interval, it will try to create one.
    # setting the sum will fail and use the one supplied,
    # but the interval entry will be added normally.
    lambda { t.record_event }.should_not raise_error('bork')
    lambda { t.record_event }.should raise_error('bork')
  end

end
