module CheckoutHelper
  def merge_order_thumbs(order)
    safe_join(order.order_items.map { |item| merge_order_thumb(item) })
  end

  def merge_order_thumb(item)
    image = item.image
    return pedido_thumb if image.blank?

    tag.span(storefront_image_tag(image, resize: 80, alt: item.name), class: "checkout__merge-thumb")
  end

  def merge_order_meta(order)
    items = order.order_items
    parts = [ t("checkout.merge.items", count: items.sum(&:quantity)) ]
    category = merge_order_category(items.first)
    parts << category if category
    parts.join(" · ")
  end

  def merge_order_category(item)
    return "Pedido de jogo" if item.custom_order?

    item.product&.category_label
  end

  private

  def pedido_thumb
    tag.span(tag.i("", class: "bi bi-card-checklist", aria: { hidden: true }),
             class: "checkout__merge-thumb checkout__merge-thumb--pedido")
  end
end
