module Account
  MockOrderItem = Data.define(:name, :unit_price_cents, :quantity, :chosen_options, :photo_path) do
    def line_total_cents
      unit_price_cents * quantity
    end
  end
end
