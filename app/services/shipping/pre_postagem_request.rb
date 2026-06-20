module Shipping
  PrePostagemRequest = Data.define(:service, :recipient, :items, :dimensions, :observacao) do
    def self.from_order(order)
      new(
        service: order.shipping_service.to_sym,
        recipient: recipient_for(order),
        items: items_for(order),
        dimensions: dimensions_for(order),
        observacao: order.number
      )
    end

    def self.recipient_for(order)
      digits = order.user.phone.to_s.gsub(/\D/, "")
      {
        nome: order.ship_receiver_name,
        dddCelular: digits[0, 2],
        celular: digits[2..],
        email: order.user.email,
        cpfCnpj: order.ship_receiver_cpf,
        endereco: {
          cep: order.ship_zip,
          logradouro: order.ship_street,
          numero: order.ship_number,
          complemento: order.ship_complement,
          bairro: order.ship_neighborhood,
          cidade: order.ship_city,
          uf: order.ship_state
        }.compact
      }
    end

    def self.items_for(order)
      order.order_items.map do |item|
        {
          conteudo: item.name,
          quantidade: item.quantity.to_s,
          valor: format("%.2f", item.unit_price_cents.fdiv(100))
        }
      end
    end

    def self.dimensions_for(order)
      {
        pesoInformado: order.shipping_weight_grams.to_s,
        alturaInformada: Shipping::PACKAGE_DIMENSIONS[:altura_cm].to_s,
        larguraInformada: Shipping::PACKAGE_DIMENSIONS[:largura_cm].to_s,
        comprimentoInformado: Shipping::PACKAGE_DIMENSIONS[:comprimento_cm].to_s
      }
    end

    private_class_method :recipient_for, :items_for, :dimensions_for
  end
end
