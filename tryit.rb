#!/usr/bin/ruby

require 'rubygems'
require 'memcache'
require 'throttle'
class Throttle::Simple < Throttle
  def test_threshold(count)
    if count > 10
      raise 'threshold'
    end
  end
end


CACHE = MemCache.new 'localhost:11211'
Throttle.set_memcache(CACHE)
t = Throttle::Simple.create(:name => 'baz2', :buckets => 10, :time_per_bucket => 1)
puts t.inspect
puts t.record_event
#10.times {t.record_event}

