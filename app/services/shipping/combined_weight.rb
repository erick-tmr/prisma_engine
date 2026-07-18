module Shipping
  module CombinedWeight
    module_function

    def call(orders:, cart:)
      existing = orders.filter_map(&:shipment).sum { |shipment| shipment.weight_grams - Shipping::PACKAGE_OVERHEAD_GRAMS }
      existing + Shipping::PackageWeight.call(cart)
    end
  end
end
