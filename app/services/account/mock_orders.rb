module Account
  # View-only mocks for the Pedidos section. No Order AR model exists yet —
  # checkout and the model land in a later feature. Templates target the shape
  # exposed by MockOrder / MockOrderItem so swapping mocks for ActiveRecord
  # later is a controller-only change.
  #
  # Order states match docs/architecture.md § 4 (the 6 customer-facing states
  # plus the two branch states); each has a pt-BR description under
  # account.orders.states.<status>.{label,description} in the locale file.
  module MockOrders
    SAMPLE_ADDRESS = {
      recipient: "Cliente Confirmado",
      street: "Rua das Flores",
      number: "150",
      complement: "Apto 12",
      neighborhood: "Centro",
      city: "São Paulo",
      state: "SP",
      zip: "01310100"
    }.freeze

    SAMPLE_ITEMS = [
      MockOrderItem.new(
        name: "Cartucho Game Boy — The Legend of Zelda: Link's Awakening DX",
        unit_price_cents: 32_000,
        quantity: 1,
        chosen_options: [ "ROM: Link's Awakening DX", "Cor da carcaça: roxo translúcido" ],
        photo_path: "/images/products/cartridge-zelda.png"
      ),
      MockOrderItem.new(
        name: "Cartucho Game Boy Color — Pokémon Crystal",
        unit_price_cents: 28_000,
        quantity: 2,
        chosen_options: [ "ROM: Pokémon Crystal", "Cor da carcaça: cristal" ],
        photo_path: "/images/products/cartridge-pokemon.png"
      )
    ].freeze

    # Real event codes from `Shipping::TrackingUpdate::EVENT_SIGNALS` (FC/82,
    # PO/01, RO/01, OEC/01, BDE/01) so the timeline previews the actual rastro
    # shape downstream Order shows will render.
    DEFINITIONS = [
      {
        number: "PG-2026-000005",
        status: "entregue",
        placed_days_ago: 18,
        items_count: 1,
        payment_method: :pix,
        payment_status: :paid,
        tracking: [
          { code: "FC",  event_type: "82", days_ago: 17, description: "Etiqueta emitida" },
          { code: "PO",  event_type: "01", days_ago: 16, description: "Postado em São Paulo / SP" },
          { code: "RO",  event_type: "01", days_ago: 14, description: "Em trânsito" },
          { code: "OEC", event_type: "01", days_ago: 12, description: "Saiu para entrega" },
          { code: "BDE", event_type: "01", days_ago: 11, description: "Entregue ao destinatário" }
        ]
      },
      {
        number: "PG-2026-000004",
        status: "enviado",
        placed_days_ago: 9,
        items_count: 2,
        payment_method: :pix,
        payment_status: :paid,
        tracking: [
          { code: "FC", event_type: "82", days_ago: 7, description: "Etiqueta emitida" },
          { code: "PO", event_type: "01", days_ago: 6, description: "Postado em São Paulo / SP" },
          { code: "RO", event_type: "01", days_ago: 4, description: "Em trânsito" }
        ]
      },
      {
        number: "PG-2026-000003",
        status: "em_producao",
        placed_days_ago: 4,
        items_count: 1,
        payment_method: :infinite_pay_card,
        payment_status: :paid,
        tracking: []
      },
      {
        number: "PG-2026-000002",
        status: "pagamento_confirmado",
        placed_days_ago: 2,
        items_count: 2,
        payment_method: :pix,
        payment_status: :paid,
        tracking: []
      },
      {
        number: "PG-2026-000001",
        status: "aguardando_pagamento",
        placed_days_ago: 0,
        items_count: 1,
        payment_method: :pix,
        payment_status: :pending,
        tracking: []
      }
    ].freeze

    SHIPPING_CENTS = 2_990

    module_function

    def all_for(_user)
      DEFINITIONS.map { |definition| build(definition) }
    end

    def find(_user, param)
      definition = DEFINITIONS.find { |d| d[:number] == param }
      definition && build(definition)
    end

    def build(definition)
      items = SAMPLE_ITEMS.first(definition[:items_count])
      subtotal = items.sum(&:line_total_cents)
      tracking_events = definition[:tracking].map do |event|
        MockOrderTrackingEvent.new(
          occurred_at: event[:days_ago].days.ago,
          code: event[:code],
          event_type: event[:event_type],
          description: event[:description]
        )
      end

      MockOrder.new(
        number: definition[:number],
        status: definition[:status],
        placed_at: definition[:placed_days_ago].days.ago,
        subtotal_cents: subtotal,
        shipping_cents: SHIPPING_CENTS,
        total_cents: subtotal + SHIPPING_CENTS,
        payment_method: definition[:payment_method],
        payment_status: definition[:payment_status],
        shipping_address: SAMPLE_ADDRESS,
        items: items,
        tracking_events: tracking_events
      )
    end
  end
end
