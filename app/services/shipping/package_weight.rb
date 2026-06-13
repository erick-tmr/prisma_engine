module Shipping
  # Total parcel weight (grams) for a Correios quote: the cart contents — scaling
  # any Game-of-the-Month brindes by line quantity — plus the fixed box + flyer
  # overhead. Shared by the cart quote endpoint and checkout's server-side
  # re-quote so both price the *same* package; if they diverged, the frete shown
  # on the cart would differ from what the order is charged.
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
