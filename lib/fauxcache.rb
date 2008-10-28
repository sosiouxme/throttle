require 'rubygems'
require 'memcache' # for the error definition
class FauxCache < Hash

  def initialize(*args)
    super
    @error = false
    @expiry = {}
  end

  def has_key?(key)
    test_for_error()
    adjust_expired(key)
    super(key)
  end

  def [](key)
    test_for_error()
    adjust_expired(key)
    super(key)
  end

  def []=(key,value)
    test_for_error()
    adjust_expired(key)
    super(key,value)
  end

  def add(key, value, exp = nil)
    if @add_error
      @add_error = false
      return false
    end
    exp += Time.now.to_i if exp && exp < Time.now.to_i
    if self.has_key? key
      return false
    else
      self[key] = value
      @expiry[key] = exp
      return true
    end
  end

  def set(key, value, exp = nil)
    exp += Time.now.to_i if exp && exp < Time.now.to_i
    self[key] = value
    @expiry[key] = exp
    true
  end

  def incr(key, value = 1)
    self[key] ? (self[key] += value) : nil
  end

  def get(*keys)
    return *keys.map { |k| self[k] }
  end

  def get_hash(*keys)
    hash = {}
    keys.each {|key| hash[key] = self[key]}
    return hash
  end

  def simulate_error_on_next
    @error = true
  end

  def simulate_add_failure
    @add_error = true
  end

protected

  def delete(key)
    @expiry.delete(key)
    super(key)
  end

  def adjust_expired(key)
    exp = @expiry[key]
    return if !exp # never expires
    return if Time.now.to_i < exp # not expired
    delete(key) #expired
  end

  def test_for_error
    return unless @error
    @error = false
    raise MemCache::MemCacheError
  end

end
