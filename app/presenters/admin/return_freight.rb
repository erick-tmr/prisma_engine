module Admin
  class ReturnFreight
    STATE_CLASSES = { "store" => "store", "pending" => "wait", "paid" => "paid", "expired" => "exp" }.freeze
    TIME_FORMAT = :day_abbr_month_at

    def initialize(shipment)
      @shipment = shipment
      @charge = shipment.freight_charge
    end

    attr_reader :shipment, :charge

    def state
      charge ? charge.state : "store"
    end

    %w[store pending paid expired].each do |name|
      define_method(:"#{name}?") { state == name }
    end

    def state_class
      STATE_CLASSES.fetch(state)
    end

    def state_label
      translate("states.#{state}")
    end

    def amount
      HasMoney.format(charge.amount_cents)
    end

    def paid_amount
      [ amount, OrderPresenter::PAYMENT_METHOD_LABELS[charge.payment_method.to_s] ].compact.join(" · ")
    end

    def cost
      [ shipment.shipping_cents && HasMoney.format(shipment.shipping_cents), service_label ].compact.join(" · ")
    end

    def service_label
      shipment.service_label
    end

    def sent_at
      stamp(charge.created_at)
    end

    def expires_at
      stamp(charge.expires_at)
    end

    def paid_at
      stamp(charge.paid_at)
    end

    def waivable?
      pending? || expired?
    end

    private

    def stamp(time)
      I18n.l(time, format: TIME_FORMAT)
    end

    def translate(key)
      I18n.t("admin.orders.detail.return_freight.#{key}")
    end
  end
end
