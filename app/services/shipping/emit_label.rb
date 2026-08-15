module Shipping
  class EmitLabel
    def self.resume(shipment)
      return unless shipment && Shipping::Leg.for(shipment).emittable?(shipment.order)

      case label_for(shipment).state
      when "pending"           then Shipping::CreatePrePostagemJob.perform_later(shipment_id: shipment.id)
      when "prepost_created"   then Shipping::ConfirmPrePostagemJob.set(wait: Shipping::PREPOSTAGEM_INITIAL_DELAY).perform_later(shipment_id: shipment.id)
      when "prepost_confirmed" then Shipping::RequestLabelJob.perform_later(shipment_id: shipment.id)
      when "requested"         then Shipping::DownloadLabelJob.perform_later(shipment_id: shipment.id)
      end
    end

    def self.recover(shipment)
      label = shipment&.shipping_label
      label.unclaim_requesting! if label&.requesting?
      resume(shipment)
    end

    def self.restart(shipment)
      shipment&.shipping_label&.ready_for_retry!
      recover(shipment)
    end

    def self.label_for(shipment)
      shipment.shipping_label || shipment.create_shipping_label!
    rescue ActiveRecord::RecordNotUnique
      shipment.reload.shipping_label
    end
    private_class_method :label_for
  end
end
