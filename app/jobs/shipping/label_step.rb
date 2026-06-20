module Shipping
  class LabelStep < ApplicationJob
    retry_on Correios::Api::TransientError,
             ActiveRecord::Deadlocked,
             ActiveRecord::LockWaitTimeout,
             wait: :polynomially_longer, attempts: 5

    limits_concurrency to: 5, key: "correios_cartao"

    def perform(order_id)
      order = Order.find_by(id: order_id)
      return unless order

      label = order.shipping_label
      return unless label && applicable?(label)

      execute(order, label)
    end

    private

    def execute(order, label)
      run(order, label)
      Shipping::EmitLabel.resume(order)
    rescue Correios::Api::TransientError
      raise
    rescue Correios::Api::Error => error
      label.record_error!(error.message)
      raise
    end
  end
end
