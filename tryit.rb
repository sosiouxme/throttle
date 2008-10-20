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
t = Throttle::Simple.create(
  :name => 'example',
  :buckets => 10,
  :time_per_bucket => 6
  # throttle over 1min period, broken into 10 intervals
)
t.record_event
puts "All's well until the next line"
10.times {t.record_event} # -> raises exception

