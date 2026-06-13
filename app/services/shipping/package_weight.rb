module Shipping
  module PackageWeight
    module_function

    def call(cart)
      gotm          = GameOfTheMonth.current.first
      gotm_ids      = gotm ? gotm.products.pluck(:id).to_set : Set.new
      brindes_grams = gotm ? gotm.brindes.sum(:weight_grams) : 0
      contents      = cart.total_weight_grams(gotm_product_ids: gotm_ids, brindes_weight_grams: brindes_grams)
      contents + Shipping::PACKAGE_OVERHEAD_GRAMS
    end
  end
end
