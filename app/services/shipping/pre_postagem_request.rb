module Shipping
  PrePostagemRequest = Data.define(:service, :sender, :recipient, :items, :dimensions, :observacao) do
    def self.from_shipment(shipment)
      order = shipment.order
      leg = Shipping::Leg.for(shipment)
      new(
        service: shipment.service.to_sym,
        **leg.parties(store: Shipping::STORE, customer: customer_for(shipment)),
        items: items_for(order),
        dimensions: dimensions_for(shipment),
        observacao: leg.observacao_for(order)
      )
    end

    def self.customer_for(shipment)
      user = shipment.order.user
      digits = phone_digits(user.phone)
      {
        nome: shipment.receiver_name,
        dddCelular: digits[0, 2],
        celular: digits[2..],
        email: user.email,
        cpfCnpj: shipment.receiver_cpf,
        obs: shipment.receiver_obs,
        endereco: {
          cep: shipment.zip,
          logradouro: shipment.street,
          numero: shipment.number,
          complemento: shipment.complement,
          bairro: shipment.neighborhood,
          cidade: shipment.city,
          uf: shipment.state
        }.compact
      }.compact
    end

    def self.phone_digits(raw)
      Phones.national(raw) || Phones.drop_country_code(raw.to_s.gsub(/\D/, ""))
    end

    def self.items_for(order)
      order.order_items.map do |item|
        {
          conteudo: sanitize_content(item.name),
          quantidade: item.quantity.to_s,
          valor: format("%.2f", item.unit_price_cents.fdiv(100))
        }
      end
    end

    def self.sanitize_content(text)
      text.to_s
          .gsub(/[‐-―]/, "-")
          .gsub(/[^ -ÿ]/, " ")
          .gsub(/\s+/, " ")
          .strip
    end

    def self.dimensions_for(shipment)
      {
        pesoInformado: shipment.weight_grams.to_s,
        alturaInformada: shipment.height_cm.to_s,
        larguraInformada: shipment.width_cm.to_s,
        comprimentoInformado: shipment.length_cm.to_s
      }
    end

    private_class_method :customer_for, :phone_digits, :items_for, :dimensions_for, :sanitize_content
  end
end
