class CheckoutController < ApplicationController
  before_action :authenticate_user!

  layout "checkout"

  # Delivery + payment screen. This is the template-first pass: the markup and
  # interactions match the Checkout.html handoff, with sample address / item /
  # shipping data rendered client-side. Wiring the real cart summary, the
  # customer's saved addresses, the Correios quote, order creation, and the
  # InfinitePay redirect is the next step.
  #
  # `@selected_shipping_service` carries the service the shopper picked on the
  # cart (stashed in the session by CartController#finalize) so the shipping
  # step opens with that option already selected.
  def show
    @selected_shipping_service = session["checkout_shipping_service"]
  end
end
