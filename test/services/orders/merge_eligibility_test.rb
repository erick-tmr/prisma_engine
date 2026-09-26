require "test_helper"

module Orders
  class MergeEligibilityTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(
        email: "eligibility@example.com", password: "password123",
        full_name: "Eligibility Cliente", cpf: "39053344705", phone: "11900000000", confirmed_at: 1.day.ago
      )
    end

    def order_in(status)
      order = @user.orders.create!(subtotal_cents: 1_000, total_cents: 1_500)
      order.update_column(:status, status)
      order.create_shipment!(
        service: "pac", shipping_cents: 500, weight_grams: 250,
        receiver_name: "Cliente", receiver_cpf: "39053344705", zip: "04534003",
        street: "Rua", number: "1", neighborhood: "Itaim", city: "São Paulo", state: "SP"
      )
      order
    end

    def reason(order, origin)
      MergeEligibility.for(order.reload, origin: origin).reason
    end

    def accepted(origin)
      verdicts = Order::STATUSES.index_with { |status| reason(order_in(status), origin) }
      assert_equal [ :status ], verdicts.values.compact.uniq
      verdicts.select { |_, verdict| verdict.nil? }.keys
    end

    test "checkout accepts only the states before production" do
      assert_equal %w[payment_confirmed awaiting_components production_issue], accepted(:checkout)
    end

    test "the backoffice also accepts orders in production and with a label issued" do
      assert_equal %w[payment_confirmed awaiting_components in_production production_issue label_issued],
                   accepted(:backoffice)
      assert MergeEligibility.for(order_in("label_issued"), origin: :backoffice).ok?
    end

    test "an order without a live shipment cannot take part" do
      order = order_in("payment_confirmed")
      order.shipment.destroy!

      assert_equal :no_shipment, reason(order, :backoffice)
    end

    test "a parcel Correios has already received is out, even before the sync moves the order" do
      order = order_in("label_issued")
      order.shipment.update!(posted_at: 1.hour.ago)
      assert_equal :posted, reason(order, :backoffice)

      order.shipment.update!(posted_at: nil, tracking_state: :in_transit)
      assert_equal :posted, reason(order, :backoffice)
    end

    test "a label still being bought blocks the merge until the saga settles" do
      order = order_in("in_production")
      label = order.shipment.create_shipping_label!(state: :prepost_created)
      assert_equal :label_in_flight, reason(order, :backoffice)

      label.update!(errored_at: Time.current, error: "boom")
      assert_nil reason(order, :backoffice)

      label.update!(errored_at: nil, error: nil, state: :ready)
      assert_nil reason(order, :backoffice)

      label.update!(state: :pending)
      order.shipment.update!(correios_status: 4)
      assert_nil reason(order, :backoffice), "an expired pré-postagem is at rest"
    end

    test "checkout never folds into an order that already has a pré-postagem" do
      order = order_in("production_issue")
      order.shipment.update!(tracking_code: "AA123456789BR")

      assert_equal :prepost, reason(order, :checkout)
      assert_nil reason(order, :backoffice)
    end

    test "the backoffice leaves alone orders tied to a checkout merge awaiting payment" do
      master = order_in("payment_confirmed")
      absorbed = order_in("awaiting_components")
      carrier = @user.orders.create!(subtotal_cents: 1_000, total_cents: 1_000)
      plan = OrderMerge.create!(
        carrier_order: carrier, master_order: master, absorbed_order_ids: [ absorbed.id ],
        combined_weight_grams: 500, combined_service: "pac", combined_shipping_cents: 900, paid_fretes_cents: 1_000
      )

      assert_equal :pending_plan, reason(master, :backoffice)
      assert_equal :pending_plan, reason(absorbed, :backoffice)
      assert_nil reason(master, :checkout), "the customer may retry the same checkout merge"

      plan.update!(executed_at: Time.current)
      assert_nil reason(master, :backoffice)
    end
  end
end
