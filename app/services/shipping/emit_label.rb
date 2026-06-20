module Shipping
  class EmitLabel
    def self.resume(order)
      label = order.shipping_label || order.create_shipping_label!
      case label.state
      when "pending"         then Shipping::CreatePrePostagemJob.perform_later(order.id)
      when "prepost_created" then Shipping::RequestLabelJob.perform_later(order.id)
      when "requested"       then Shipping::DownloadLabelJob.perform_later(order.id)
      end
    end
  end
end
