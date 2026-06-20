class OrderStatusChange < ApplicationRecord
  belongs_to :order
  belongs_to :actor, class_name: "User", optional: true

  validates :to_status, presence: true

  scope :chronological, -> { order(:created_at, :id) }
end
