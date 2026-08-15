module Shipping
  class LabelStep < ApplicationJob
    MAX_RELABEL_ATTEMPTS = 3

    retry_on Correios::Api::TransientError,
             ActiveRecord::Deadlocked,
             ActiveRecord::LockWaitTimeout,
             wait: :polynomially_longer, attempts: 5

    limits_concurrency to: 5, key: "correios_cartao"

    def perform(shipment_id:)
      shipment = Shipment.find_by(id: shipment_id)
      return unless shipment

      label = shipment.shipping_label
      return unless label && applicable?(label)

      execute(shipment, label)
    end

    private

    def execute(shipment, label)
      run(shipment, label)
      Shipping::EmitLabel.resume(shipment)
    rescue Correios::Api::TransientError
      raise
    rescue Correios::Api::LabelGenerationFailedError => error
      relabel(shipment, label, error)
    rescue Correios::Api::Error => error
      label.record_error!(error.message)
      raise
    end

    def relabel(shipment, label, error)
      if label.relabel_attempts >= MAX_RELABEL_ATTEMPTS
        label.record_error!(error.message)
        raise error
      end

      label.reset_for_relabel!
      Shipping::EmitLabel.resume(shipment)
    end
  end
end
