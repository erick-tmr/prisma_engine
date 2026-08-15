module Shipping
  class EmitLabel
    def self.resume(order)
      shipment = order.shipment
      return unless shipment && order.shippable?

      case label_for(shipment).state
      when "pending"           then Shipping::CreatePrePostagemJob.perform_later(order.id)
      when "prepost_created"   then Shipping::ConfirmPrePostagemJob.set(wait: Shipping::PREPOSTAGEM_INITIAL_DELAY).perform_later(order.id)
      when "prepost_confirmed" then Shipping::RequestLabelJob.perform_later(order.id)
      when "requested"         then Shipping::DownloadLabelJob.perform_later(order.id)
      end
    end

    def self.recover(order)
      label = order.shipment&.shipping_label
      label.unclaim_requesting! if label&.requesting?
      resume(order)
    end

    def self.restart(order)
      order.shipment&.shipping_label&.ready_for_retry!
      recover(order)
    end

    def self.label_for(shipment)
      shipment.shipping_label || shipment.create_shipping_label!
    rescue ActiveRecord::RecordNotUnique
      shipment.reload.shipping_label
    end
    private_class_method :label_for
  end
end
