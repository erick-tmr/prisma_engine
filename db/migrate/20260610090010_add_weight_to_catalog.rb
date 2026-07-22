class AddWeightToCatalog < ActiveRecord::Migration[8.1]
  # weight_grams lands on products NOT NULL; existing rows backfill to 22g
  # (PCB + shell baseline per the cart spec). Options + brindes default 0 and
  # we lift "Com caixa" to 38g; every other existing option matches the base
  # game weight, so 0 is the right starting point.
  def change
    add_column :products,        :weight_grams,        :integer
    add_column :product_options, :weight_delta_grams,  :integer, null: false, default: 0
    add_column :brindes,         :weight_grams,        :integer, null: false, default: 0

    reversible do |dir|
      dir.up do
        Product.unscoped.in_batches.update_all(weight_grams: 22)
        ProductOption.unscoped.where(name: "Com caixa").update_all(weight_delta_grams: 38)
      end
    end

    change_column_null :products, :weight_grams, false
  end
end
