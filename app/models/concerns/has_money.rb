module HasMoney
  extend ActiveSupport::Concern

  def self.format(cents)
    "R$ %0.2f" % (cents.to_i / 100.0)
  end

  class_methods do
    def money_attribute(cents_attr, as:)
      define_method(as) do
        HasMoney.format(public_send(cents_attr))
      end
    end
  end
end
