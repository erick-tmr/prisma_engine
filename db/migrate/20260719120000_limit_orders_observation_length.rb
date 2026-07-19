class LimitOrdersObservationLength < ActiveRecord::Migration[8.0]
  def change
    add_check_constraint :orders,
                         "char_length(observation) <= 1400",
                         name: "orders_observation_length"
  end
end
