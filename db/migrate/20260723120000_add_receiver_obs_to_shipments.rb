class AddReceiverObsToShipments < ActiveRecord::Migration[8.1]
  def change
    add_column :shipments, :receiver_obs, :string, limit: 100
  end
end
