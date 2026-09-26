module Shipping
  module CombinedService
    SERVICE_TIERS = { "mini_envios" => 0, "pac" => 1, "sedex" => 2 }.freeze

    module_function

    def call(orders:, weight_grams:)
      floor = orders.map { |order| tier(order.shipment.service) }.max
      Shipping::Quote.call(cep_destino: orders.first.shipment.zip, weight_grams: weight_grams)
                     .select { |service| service[:eligible] && tier(service[:key].to_s) >= floor }
                     .min_by { |service| service[:price_cents] }
    end

    def tier(service)
      SERVICE_TIERS.fetch(service, 0)
    end
  end
end
