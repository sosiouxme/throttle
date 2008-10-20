require File.dirname(__FILE__) + '/spec_helper.rb'

describe "Throttle.new" do

  it "should exist" do
    Throttle.new.should be_an_instance_of(Throttle)
  end

  it "should read its args" do
    t = Throttle.new(
          :name => 'test',
          :buckets => 10,
          :time_per_bucket => 60
          )
    t.name.should == 'test'
    t.buckets.should == 10
    t.time_per_bucket.should == 60
  end

  it "should work with a block" do
    t = Throttle.new { a = 1 }
    t.should_not == nil
  end

  it "should work with threshold callbacks" do
    t = Throttle.new(1 => lambda { sleep(1) })
    t.should_not == nil
  end

  it "should fail gracefully if memcached isn't working" do
    @cache.simulate_error_on_next
    lambda { t = Throttle.new }.should_not raise_error()
  end
end

class Simple1 < Throttle
  def test_threshold(count)
    raise 'bork'
  end
end

class Simple2 < Throttle
  def test_threshold(count)
    raise 'bork' if count > 10
  end
end

describe "a throttle" do
  it "should call test_threshold for every event" do
    t = Simple1.new
    lambda { t.record_event }.should raise_error('bork')
  end

  it "should run the count up to the threshold" do
    t = Simple2.new
    lambda { 10.times {t.record_event} }.should_not raise_error('bork')
    lambda { t.record_event }.should raise_error('bork')
  end

  it "should work with a singleton threshold method" do
    t = Throttle.new
    def t.test_threshold(count)
      raise 'bork' if count > 1
    end
    lambda { t.record_event }.should_not raise_error('bork')
    lambda { t.record_event }.should raise_error('bork')
  end

  it "should work with threshold callbacks" do
    t = Throttle.new(
      1 => lambda { raise 'bork1' },
      2 => lambda { |c| raise 'bork2' }
    )
    lambda { t.record_event }.should raise_error('bork1')
    lambda { t.record_event }.should raise_error('bork2')
  end

  it "should call a block if given" do
    a = 0
    t = Throttle.new { a = 1 }
    t.record_event
    a.should == 1
  end

  it "should fail gracefully when memcache fails" do
    t = Throttle.new
    def t.test_threshold(count)
      raise 'bork'
    end
    @cache.simulate_error_on_next
    lambda { t.record_event }.should_not raise_error()
  end

end
