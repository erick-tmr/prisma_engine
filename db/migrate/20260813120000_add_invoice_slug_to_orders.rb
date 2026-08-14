class AddInvoiceSlugToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :invoice_slug, :string
  end
end
