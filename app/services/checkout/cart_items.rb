module Checkout
  module CartItems
    module_function

    def attributes_for(line)
      product = line.product
      {
        product_id:       product.id,
        name:             product.title,
        unit_price_cents: line.unit_price_cents,
        quantity:         line.quantity,
        chosen_options:   line.options.map { |opt| opt.group_name.present? ? "#{opt.group_name}: #{opt.name}" : opt.name },
        requested_game:   line.requested_game,
        request_notes:    line.request_notes
      }
    end
  end
end
