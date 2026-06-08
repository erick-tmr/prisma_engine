module Account
  MockOrder = Data.define(
    :number, :status, :placed_at, :subtotal_cents, :shipping_cents, :total_cents,
    :payment_method, :payment_status, :shipping_address, :items, :tracking_events
  ) do
    def to_param
      number
    end

    # Cancellation window closes at em_producao per arch § 0.1.
    def cancellable?
      %w[aguardando_pagamento pagamento_confirmado].include?(status)
    end

    def shipping_visible?
      %w[enviado entregue].include?(status)
    end
  end
end
