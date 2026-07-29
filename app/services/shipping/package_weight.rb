module Shipping
  module PackageWeight
    module_function

    def call(cart)
      gotm     = GameOfTheMonth.current.includes(published_picks: :brindes).first
      weights  = gotm ? brindes_weight_by_product_id(gotm) : {}
      contents = cart.total_weight_grams(gotm_brindes_weight_by_product_id: weights)
      contents + Shipping::PACKAGE_OVERHEAD_GRAMS
    end

    def brindes_weight_by_product_id(gotm)
      gotm.published_picks.to_h { |gp| [ gp.product_id, gp.brindes.sum(&:weight_grams) ] }
    end
  end
end
