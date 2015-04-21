module Contracts
  module Eigenclass
    def self.extended(eigenclass)
      return if eigenclass.respond_to?(:__contracts_ruby)

      class << eigenclass
        def __contracts_ruby
          @___contracts_ruby ||= Contracts::MethodDecorators::Engine.new(self)
        end
      end
    end

    def self.lift(base)
      return NullEigenclass if Support.eigenclass? base

      eigenclass = Support.eigenclass_of base

      eigenclass.extend(Eigenclass) unless eigenclass.respond_to?(:__contracts_ruby)

      unless eigenclass.__contracts_ruby.extended
        eigenclass.extend(MethodDecorators)
        eigenclass.send(:include, Contracts)
      end

      eigenclass.__contracts_ruby.owner_class = base

      eigenclass
    end

    module NullEigenclass
      def self.__contracts_ruby
        self
      end

      def self.owner_class
        self
      end

      def self.pop_decorators
        []
      end
    end
  end
end
