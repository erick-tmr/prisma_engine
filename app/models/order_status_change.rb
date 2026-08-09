class OrderStatusChange < ApplicationRecord
  NOTIFIED = {
    "payment_confirmed" => :payment_confirmed,
    "label_issued"      => :label_issued,
    "shipped"           => :shipped,
    "delivered"         => :delivered,
    "delivery_issue"    => :delivery_issue,
    "returned"          => :returned
  }.freeze

  belongs_to :order
  belongs_to :actor, class_name: "User", optional: true

  validates :to_status, presence: true

  scope :chronological, -> { order(:created_at, :id) }

  after_create_commit :deliver_order_email

  private

  def deliver_order_email
    action = NOTIFIED[to_status]
    return unless action
    return unless order.reload.status == to_status

    OrderMailer.public_send(action, order).deliver_later
  end
end
