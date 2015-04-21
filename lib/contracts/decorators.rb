module Contracts
  module MethodDecorators
    class Engine
      attr_accessor :owner_class
      attr_accessor :extended
      attr_reader :target

      def initialize(target)
        @target = target
      end

      def pop_decorators
        Array(@decorators).tap { @decorators = nil }
      end

      def fetch_decorators
        pop_decorators + Eigenclass.lift(target).__contracts_ruby.pop_decorators
      end

      def decorated_methods
        @_decorated_methods ||= { :class_methods => {}, :instance_methods => {} }
      end

      def decorate(klass, *args)
        if Support.eigenclass? target
          return EigenclassWithOwner.lift(target).__contracts_ruby.owner_class.__contracts_ruby.decorate(klass, *args)
        end

        @decorators ||= []
        @decorators << [klass, args]
      end

      def common_method_added(name, is_class_method)
        decorators = fetch_decorators
        return if decorators.empty?

        if is_class_method
          method_reference = SingletonMethodReference.new(name, target.method(name))
          method_type = :class_methods
        else
          method_reference = MethodReference.new(name, target.instance_method(name))
          method_type = :instance_methods
        end

        decorated_methods[method_type][name] ||= []

        pattern_matching = false
        decorators.each do |klass, args|
          # a reference to the method gets passed into the contract here. This is good because
          # we are going to redefine this method with a new name below...so this reference is
          # now the *only* reference to the old method that exists.
          # We assume here that the decorator (klass) responds to .new
          decorator = klass.new(target, method_reference, *args)
          decorated_methods[method_type][name] << decorator
          pattern_matching ||= decorator.pattern_match?
        end

        if decorated_methods[method_type][name].any? { |x| x.method != method_reference }
          decorated_methods[method_type][name].each(&:pattern_match!)

          pattern_matching = true
        end

        method_reference.make_alias(target)

        return if ENV["NO_CONTRACTS"] && !pattern_matching

        # in place of this method, we are going to define our own method. This method
        # just calls the decorator passing in all args that were to be passed into the method.
        # The decorator in turn has a reference to the actual method, so it can call it
        # on its own, after doing it's decorating of course.

        current = target
        method_reference.make_definition(target) do |*args, &blk|
          ancestors = current.ancestors
          ancestors.shift # first one is just the class itself
          while current && !current.respond_to?(:__contracts_ruby) ||
              current && current.__contracts_ruby.decorated_methods.nil?
            current = ancestors.shift
          end

          if !current.respond_to?(:__contracts_ruby) || current && current.__contracts_ruby.decorated_methods.nil?
            fail "Couldn't find decorator for method " + self.class.name + ":#{name}.\nDoes this method look correct to you? If you are using contracts from rspec, rspec wraps classes in it's own class.\nLook at the specs for contracts.ruby as an example of how to write contracts in this case."
          end

          methods = current.__contracts_ruby.decorated_methods[method_type][name]

          # this adds support for overloading methods. Here we go through each method and call it with the arguments.
          # If we get a ContractError, we move to the next function. Otherwise we return the result.
          # If we run out of functions, we raise the last ContractError.
          success = false
          i = 0
          result = nil
          expected_error = methods[0].failure_exception
          until success
            method = methods[i]
            i += 1
            begin
              success = true
              result = method.call_with(self, *args, &blk)
            rescue expected_error => error
              success = false
              unless methods[i]
                begin
                  ::Contract.failure_callback(error.data, false)
                rescue expected_error => final_error
                  raise final_error.to_contract_error
                end
              end
            end
          end
          result
        end
      end

    end

    def self.extended(klass)
      return if klass.respond_to?(:__contracts_ruby)

      class << klass
        def __contracts_ruby
          @___contracts_ruby ||= Engine.new(self)
        end
      end

      klass.__contracts_ruby.extended = true
    end

    module EigenclassWithOwner
      def self.lift(eigenclass)
        fail Contracts::ContractsNotIncluded unless with_owner?(eigenclass)

        eigenclass
      end

      private

      def self.with_owner?(eigenclass)
        eigenclass.respond_to?(:__contracts_ruby) && eigenclass.__contracts_ruby.owner_class
      end
    end

    # first, when you write a contract, the decorate method gets called which
    # sets the @decorators variable. Then when the next method after the contract
    # is defined, method_added is called and we look at the @decorators variable
    # to find the decorator for that method. This is how we associate decorators
    # with methods.
    def method_added(name)
      __contracts_ruby.common_method_added name, false
      super
    end

    def singleton_method_added(name)
      __contracts_ruby.common_method_added name, true
      super
    end
  end

  class Decorator
    # an attr_accessor for a class variable:
    class << self; attr_accessor :decorators; end

    def self.inherited(klass)
      name = klass.name.gsub(/^./) { |m| m.downcase }

      return if name =~ /^[^A-Za-z_]/ || name =~ /[^0-9A-Za-z_]/

      # the file and line parameters set the text for error messages
      # make a new method that is the name of your decorator.
      # that method accepts random args and a block.
      # inside, `decorate` is called with those params.
      MethodDecorators.module_eval <<-ruby_eval, __FILE__, __LINE__ + 1
        def #{klass}(*args, &blk)
          __contracts_ruby.decorate(#{klass}, *args, &blk)
        end
      ruby_eval
    end

    def initialize(klass, method)
      @method = method
    end
  end
end
