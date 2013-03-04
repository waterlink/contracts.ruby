module MethodDecorators
  def self.extended(klass)
    klass.class_eval do
      @@__decorated_methods ||= {}
      def self.__decorated_methods
        @@__decorated_methods
      end

      def self.__decorated_methods_set(k, v)
        @@__decorated_methods[k] = v
      end
    end
  end

  # first, when you write a contract, the decorate method gets called which
  # sets the @decorators variable. Then when the next method after the contract
  # is defined, method_added is called and we look at the @decorators variable
  # to find the decorator for that method. This is how we associate decorators
  # with methods.
  def method_added(name)
    common_method_added name, false
    super
  end

  # For Ruby 1.9
  def singleton_method_added name
    common_method_added name, true
    super
  end

  def common_method_added name, is_class_method
    return unless @decorators

    decorators = @decorators.dup
    @decorators = nil

    decorators.each do |klass, args|
      # a reference to the method gets passed into the contract here. This is good because
      # we are going to redefine this method with a new name below...so this reference is
      # now the *only* reference to the old method that exists.
    if args[-1].is_a? Hash
      # internally we just convert that return value syntax back to an array
      contracts = args[0, args.size - 1] + args[-1].keys
    else
      fail "It looks like your contract for #{method} doesn't have a return value. A contract should be written as `Contract arg1, arg2 => return_value`."
    end
      
      validators = contracts.map do |contract|
        Contract.make_validator(contract)
      end
      decorator = {
        :klass => self,
        :args_contracts => contracts[0, contracts.size - 1],
        :ret_contract => contracts[-1],
        :args_validators => validators[0, validators.size - 1],
        :ret_validator => validators[-1]
      }
      if is_class_method
        decorator[:method] = :"old_#{name}"
      else
        decorator[:method] = :"old_#{name}"
      end
      __decorated_methods_set(name, decorator)
    end

    alias_method :"old_#{name}", name

    # in place of this method, we are going to define our own method. This method
    # just calls the decorator passing in all args that were to be passed into the method.
    # The decorator in turn has a reference to the actual method, so it can call it
    # on its own, after doing it's decorating of course.
    foo = %{
      def #{is_class_method ? "self." : ""}#{name}(*args, &blk)
        this = self#{is_class_method ? "" : ".class"}
        hash = this.__decorated_methods[#{name.inspect}]

        _args = blk ? args + [blk] : args

        # check contracts on arguments
        # fun fact! This is significantly faster than .zip (3.7 secs vs 4.7 secs). Why??
        last_index = hash[:args_validators].size - 1
        # times is faster than (0..args.size).each
        _args.size.times do |i|
          # this is done to account for extra args (for *args)
          j = i < last_index ? i : last_index
          unless hash[:args_validators][j][_args[i]]
            call_function = Contract.failure_callback({:arg => _args[i], :contract => hash[:args_contracts][j], :class => this, :method => hash[:method], :contracts => (hash[:args_contracts] + hash[:ret_contract])})
            return unless call_function
          end
        end

        #result = hash[:method].bind(self).call(*args, &blk)
        result = this.send(hash[:method], *args, &blk)
        unless hash[:ret_validator][result]
          Contract.failure_callback({:arg => result, :contract => hash[:ret_contract], :class => this, :method => hash[:method], :contracts => (hash[:args_contracts] + hash[:ret_contract])})
        end            
        result
      end
      }
      
      class_eval foo, __FILE__, __LINE__ + 1
  end    

  def decorate(klass, *args)
    @decorators ||= []
    @decorators << [klass, args]
  end
end

class Decorator
  # an attr_accessor for a class variable:
  class << self; attr_accessor :decorators; end

  def self.inherited(klass)
    name = klass.name.gsub(/^./) {|m| m.downcase}

    return if name =~ /^[^A-Za-z_]/ || name =~ /[^0-9A-Za-z_]/

    # the file and line parameters set the text for error messages
    # make a new method that is the name of your decorator.
    # that method accepts random args and a block.
    # inside, `decorate` is called with those params.
    MethodDecorators.module_eval <<-ruby_eval, __FILE__, __LINE__ + 1
      def #{klass}(*args, &blk)
        decorate(#{klass}, *args, &blk)
      end
    ruby_eval
  end

  def initialize(klass, method)
    @method = method
  end
end
