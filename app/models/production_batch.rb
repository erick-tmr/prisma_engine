class ProductionBatch < ApplicationRecord
  belongs_to :operator, class_name: "User", optional: true
  has_many :orders, dependent: :nullify

  scope :recent_first, -> { order(created_at: :desc) }
end
