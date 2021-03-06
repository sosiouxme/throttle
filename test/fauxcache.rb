require File.dirname(__FILE__) + '/spec_helper.rb'

describe "the faux cache" do

  it "should work like a Memcache object" do
    @cache.set('key', 'value')
    @cache.get('key').should == 'value'
    @cache.set('key2', 0, Time.now.to_i + 1)
    @cache.incr('key2').should == 1
    @cache.incr('key2').should == 2
    @cache.incr('key3').should == nil
  end

  it "should raise an exception when requested" do
    @cache.simulate_error_on_next
    lambda { @cache.incr('key') }.should raise_error(MemCache::MemCacheError)
  end

  it "should fail an add when requested" do
    @cache.simulate_add_failure
    @cache.add('key','value').should == false
    @cache.add('key','value').should == true
  end

  it "should expire entries" do
    @cache.set('key','value',Time.now.to_i + 1)
    @cache.get('key').should == 'value'
    sleep(1)
    @cache.get('key').should == nil
  end

end
