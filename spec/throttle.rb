require File.dirname(__FILE__) + '/spec_helper.rb'

describe "a new throttle" do

  it "should exist" do
    Throttle.new.should be_an_instance_of(Throttle)
  end

  it "should read its args" do
    t = Throttle.create(
          :name => 'test',
          :buckets => 10,
          :time_per_bucket => 60
          )
    t.name.should == 'test'
    t.buckets.should == 10
    t.time_per_bucket.should == 60
  end

  it "should work with a block" do
    Throttle.create { puts "hi" }.should_not == nil
  end

  it "should be storable" do
    Throttle.new.store.should_not == nil
  end

  it "should be retrievable" do
    Throttle.new(:name => 'foo').store.should_not == nil
    Throttle.retrieve('foo').should_not == nil
  end

  it "should be created, then found in the cache" do
    t = Throttle.create(:name => 'foo')
    t2 = Throttle.create(:name => 'foo')
    t2.should.equal?(t)
  end

  it "should fail gracefully if memcached isn't working" do
    @cache.simulate_error_on_next
    lambda { t = Throttle.create }.should_not raise_error()
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
  it "should call the proc for every event" do
    t = Simple1.create
    lambda { t.record_event }.should raise_error('bork')
  end

  it "should run the count up to the threshold" do
    t = Simple2.create
    lambda { 10.times {t.record_event} }.should_not raise_error('bork')
    lambda { t.record_event }.should raise_error('bork')
  end

  it "should work with a singleton threshold method" do
    t = Throttle.create
    def t.test_threshold(count)
      raise 'bork' if count > 1
    end
    lambda { t.record_event }.should_not raise_error('bork')
    lambda { t.record_event }.should raise_error('bork')
  end

end
