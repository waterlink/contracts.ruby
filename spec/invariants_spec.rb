module Contracts
  RSpec.describe Invariants do

    subject { MyBirthday.new(31, 12) }

    it "works when all invariants are holding" do
      expect { subject.clever_next_day! }.not_to raise_error
      expect { subject.clever_next_month! }.not_to raise_error
    end

    it "raises invariant violation error when any of invariants are not holding" do
      expect { subject.silly_next_day! }.to raise_error(InvariantError, /day/)
      expect { subject.silly_next_month! }.to raise_error(InvariantError, /month/)
    end

  end
end
