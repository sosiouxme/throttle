require 'rubygems'
require 'memcache'
require 'spec'
require 'flexmock/test_unit'
require 'lib/throttle'
require 'lib/fauxcache'

if !defined? CACHE
  CACHE = ENV['TEST_MEMCACHE'] ? MemCache.new('localhost:11211') : nil
end

Spec::Runner.configure do |config|
  config.before :each do
    # start with a fresh cache for each example
    Throttle.memcache = @cache = FauxCache.new
    if CACHE
      Throttle.memcache = CACHE
      Throttle.memcache.flush_all
    end
  end
end

