require 'benchmark'

module Wrapper
  def self.extended(klass)
    klass.class_eval do
      @@methods = {}
      def self.methods
        @@methods
      end
      def self.set_method k, v
        @@methods[k] = v
      end
    end
  end

  def method_added name
    return if methods.include?(name)
    puts "#{name} added"
    set_method(name, instance_method(name))
    class_eval %{
      def #{name}(*args)
        self.class.methods[#{name.inspect}].bind(self).call(*args)
      end
    }, __FILE__, __LINE__ + 1
  end
end

module Wrapper2
  def self.extended(klass)
    klass.class_eval do
      @@methods = []
      def self.methods
        @@methods
      end
      def self.add_method name
        @@methods << name
      end
    end
  end

  def method_added name
    return if methods.include?(name) || name =~ /original/
    puts "#{name} added2"
    add_method(name)
    alias_method :"original_#{name}", name    
    define_method name do |*args|
      self.send :"original_#{name}", *args
    end    
  end
end

class NotWrapped
def add a, b
  a + b
end
end

class Wrapped
  extend ::Wrapper
  def add a, b
    a + b
  end
end

class Wrapped2
  extend ::Wrapper2
  def add a, b
    a + b
  end
end

w = Wrapped.new
nw = NotWrapped.new
# 30 is the width of the output column
Benchmark.bm 30 do |x|
  x.report 'wrapped' do
    1000000.times do |_|
      w.add(rand(1000), rand(1000))
    end
  end
  x.report 'not wrapped' do
    1000000.times do |_|
      nw.add(rand(1000), rand(1000))      
    end
  end
end

