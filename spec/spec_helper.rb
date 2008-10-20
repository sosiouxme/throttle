require 'rubygems'
require 'memcache' # for the error definition
require 'throttle'
class MockMemcache < Hash

  def initialize(*args)
    super
    @error = false
  end

  def set(key, value, exp = nil)
    test_for_error()
    exp += Time.now.to_i if exp && exp < Time.now.to_i
    self[key] = [value, exp]
    value
  end

  def incr(key, value = 1)
    test_for_error()
    adjust_expired(key)
    self[key] ? (self[key][0] += value) : nil
  end

  def get(*keys)
    test_for_error()
    values = keys.map do |k|
      adjust_expired(k)
      self[k] ? self[k][0] : nil
    end

    return *values
  end

  def simulate_error_on_next
    @error = true
  end
  def test_for_error
    return unless @error
    @error = false
    raise MemCache::MemCacheError
  end

  protected
  def adjust_expired(key)
    v = self[key]
    return if !v
    return if v[1] == nil || Time.now.to_i < v[1] # not expired
    self.delete(key) #expired
  end

end

Spec::Runner.configure do |config|
  config.before :each do
    Throttle.set_memcache(@cache = MockMemcache.new)
  end
end

