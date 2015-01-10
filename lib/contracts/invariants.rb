class InvariantError < StandardError
  def to_contract_error
    self
  end
end

module Contracts
  module Invariants
  end
end

class Invariant < Contracts::Decorator
  def initialize(klass, method, name, &condition)
    @klass, @method, @name, @condition = klass, method, name, condition
  end

  def to_s
    "#{@name} condition"
  end
end
