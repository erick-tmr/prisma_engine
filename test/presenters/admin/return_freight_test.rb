require "test_helper"

module Admin
  class ReturnFreightTest < ActiveSupport::TestCase
    setup do
      @shipment = Shipment.create!(order: orders(:delivered), direction: :inbound, service: "mini_envios",
                                   shipping_cents: 1490)
    end

    test "a store-paid return shows what it cost the store" do
      freight = ReturnFreight.new(@shipment)

      assert freight.store?
      assert_equal "store", freight.state_class
      assert_equal "Loja paga", freight.state_label
      assert_equal "R$ 14,90 · Mini Envios", freight.cost
      assert_not freight.waivable?
    end

    test "an unquoted store-paid return still names the service" do
      @shipment.update!(shipping_cents: nil)

      assert_equal "Mini Envios", ReturnFreight.new(@shipment).cost
    end

    test "a pending charge shows its link window" do
      charge = ReturnFreightCharge.issue(shipment: @shipment, amount_cents: 1490,
                                         at: Time.zone.parse("2026-09-25 10:42"))
      travel_to charge.created_at + 1.hour do
        freight = ReturnFreight.new(@shipment)

        assert freight.pending?
        assert_equal "wait", freight.state_class
        assert_equal "Pendente", freight.state_label
        assert_equal "R$ 14,90", freight.amount
        assert_equal "Mini Envios", freight.service_label
        assert_equal "25 set, 10:42", freight.sent_at
        assert_equal "28 set, 10:42", freight.expires_at
        assert freight.waivable?
      end
    end

    test "an expired charge can still be assumed" do
      ReturnFreightCharge.issue(shipment: @shipment, amount_cents: 1490, at: 4.days.ago)
      freight = ReturnFreight.new(@shipment)

      assert freight.expired?
      assert_equal "exp", freight.state_class
      assert freight.waivable?
    end

    test "a paid charge shows how and when it was paid" do
      charge = ReturnFreightCharge.issue(shipment: @shipment, amount_cents: 1490)
      charge.update!(paid_at: Time.zone.parse("2026-09-25 14:07"), payment_method: "pix")
      freight = ReturnFreight.new(@shipment)

      assert freight.paid?
      assert_equal "paid", freight.state_class
      assert_equal "R$ 14,90 · Pix", freight.paid_amount
      assert_equal "25 set, 14:07", freight.paid_at
      assert_not freight.waivable?

      charge.update!(payment_method: nil)
      assert_equal "R$ 14,90", ReturnFreight.new(@shipment).paid_amount
    end
  end
end
