class AddDeliveryBusinessDaysToShipments < ActiveRecord::Migration[8.1]
  def change
    add_column :shipments, :delivery_business_days, :integer
  end
end
