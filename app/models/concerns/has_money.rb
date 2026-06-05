module HasMoney
  extend ActiveSupport::Concern

  class_methods do
    # Defines a `R$ 1.234,56`-style formatter over an integer cents column,
    # reproducing the legacy PORO behaviour exactly: zero reads "Sob consulta".
    def money_attribute(cents_attr, as:)
      define_method(as) do
        cents = public_send(cents_attr).to_i
        return "Sob consulta" if cents.zero?

        "R$ %0.2f" % (cents / 100.0)
      end
    end
  end
end
