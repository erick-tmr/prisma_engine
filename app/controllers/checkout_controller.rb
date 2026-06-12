class CheckoutController < ApplicationController
  before_action :authenticate_user!

  layout "checkout"

  # Delivery + payment screen. This is the template-first pass: the markup and
  # interactions match the Checkout.html handoff, with sample address / item /
  # shipping data rendered client-side. Wiring the real cart summary, the
  # customer's saved addresses, the Correios quote, order creation, and the
  # InfinitePay redirect is the next step.
  def show
  end
end
