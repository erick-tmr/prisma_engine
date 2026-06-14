module RemembersShipping
  private

  def remember_shipping_choice
    service = params[:shipping_service].to_s
    if Shipping::SERVICES.keys.any? { |key| key.to_s == service }
      session["checkout_shipping_service"] = service
    else
      session.delete("checkout_shipping_service")
    end
  end
end
