module Shipping
  module PackageWeight
    module_function

    def call(cart)
      gotm     = GameOfTheMonth.current.includes(game_of_the_month_products: :brindes).first
      weights  = gotm ? brindes_weight_by_product_id(gotm) : {}
      contents = cart.total_weight_grams(gotm_brindes_weight_by_product_id: weights)
      contents + Shipping::PACKAGE_OVERHEAD_GRAMS
    end

    def brindes_weight_by_product_id(gotm)
      gotm.game_of_the_month_products.to_h { |gp| [ gp.product_id, gp.brindes.sum(&:weight_grams) ] }
    end
  end
end
