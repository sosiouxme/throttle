#!/usr/bin/ruby

require 'rubygems'
require 'memcache'
require 'throttle'

CACHE = MemCache.new 'localhost:11211'
Throttle.memcache = CACHE
t = Throttle.new(
  :name => 'example',
  :buckets => 10,
  :time_per_bucket => 6
  # throttle over 1min period, broken into 10 intervals
) {|count,th| raise 'threshold' if count > 10}
t.record_event
puts "All's well until the next line"
10.times {t.record_event} # -> raises exception

