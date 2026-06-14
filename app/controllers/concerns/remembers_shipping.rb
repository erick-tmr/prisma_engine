module RemembersShipping
  private

  # Bridge the cart's client-side frete pick to the checkout screen, which
  # reads it back to pre-select the same service. Whitelisted against our
  # known services so a hand-edited form can't stash arbitrary input; the
  # binding re-validation against a fresh quote still happens at order time.
  def remember_shipping_choice
    service = params[:shipping_service].to_s
    if Shipping::SERVICES.keys.any? { |key| key.to_s == service }
      session["checkout_shipping_service"] = service
    else
      session.delete("checkout_shipping_service")
    end
  end
end
