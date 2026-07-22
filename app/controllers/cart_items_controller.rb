class CartItemsController < ApplicationController
  include RemembersShipping

  def create
    # Products are public catalog rows, not user-scoped; an "unscoped" find
    # on a published product is the expected lookup for any shopper.
    # nosemgrep: ruby.rails.security.brakeman.check-unscoped-find.check-unscoped-find
    product = Product.published.find(params[:product_id])
    if product.custom_order? && params.dig(:request, :game).to_s.strip.empty?
      flash[:error] = product.custom_order_text.text(:game_error)
      # nosemgrep: ruby.rails.security.audit.xss.avoid-redirect.avoid-redirect
      return redirect_to product_path(product)
    end
    cart = current_cart
    cart.add(
      product:    product,
      quantity:   params[:quantity],
      option_ids: validated_option_ids(product, params[:option_ids]),
      request:    request_for(product)
    )
    persist!(cart)
    flash[:cart_added] = "Produto adicionado ao carrinho."
    # nosemgrep: ruby.rails.security.audit.xss.avoid-redirect.avoid-redirect
    redirect_to product_path(product)
  end

  def update
    cart = current_cart
    if params.key?(:quantity)
      cart.update_quantity(params[:id], params[:quantity])
    end
    if params.key?(:option_ids)
      product = product_for_line(cart, params[:id])
      if product
        cart.update_options(params[:id], validated_option_ids(product, params[:option_ids]))
      end
    end
    remember_shipping_choice if params.key?(:shipping_service)
    persist!(cart)
    redirect_to "/carrinho"
  end

  def destroy
    cart = current_cart
    cart.remove(params[:id])
    persist!(cart)
    redirect_to "/carrinho", notice: "Item removido do carrinho."
  end

  private

  def persist!(cart)
    cookies.signed[:cart] = { value: cart.to_cookie, expires: 30.days.from_now }
  end

  # Only keep option ids that actually belong to the product. Belt-and-braces
  # against direct POSTs that try to attach a foreign option for a free price
  # delta — the PDP form already submits valid ids.
  def validated_option_ids(product, raw)
    valid_ids = product.product_options.pluck(:id).to_set
    Array(raw).map(&:to_i).select { |id| valid_ids.include?(id) }
  end

  def request_for(product)
    return nil unless product.custom_order?
    { game: params.dig(:request, :game), notes: params.dig(:request, :notes) }
  end

  def product_for_line(cart, line_id)
    item = cart.items.find { |it| it["id"] == line_id.to_s }
    return nil unless item
    Product.find_by(id: item["p"])
  end
end
