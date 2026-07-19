require "test_helper"

module Orders
  class MergeTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(
        email: "merge@example.com", password: "password123",
        full_name: "Merge Cliente", cpf: "39053344705", phone: "11900000000", confirmed_at: 1.day.ago
      )
      @master   = build_order(status: "payment_confirmed", frete: 500, item_price: 10_000, item_qty: 1, created: 3.days.ago)
      @absorbed = build_order(status: "awaiting_components", frete: 700, item_price: 5_000, item_qty: 2, created: 2.days.ago)
      @carrier  = build_carrier(item_price: 3_000)
      @plan = OrderMerge.create!(
        carrier_order: @carrier, master_order: @master, absorbed_order_ids: [ @absorbed.id ],
        combined_weight_grams: 508, combined_service: "pac",
        combined_shipping_cents: 2384, paid_fretes_cents: 1200
      )
    end

    def build_order(status:, frete:, item_price:, item_qty:, created:)
      order = @user.orders.create!(subtotal_cents: item_price * item_qty, total_cents: item_price * item_qty + frete, status: status)
      order.update_column(:created_at, created)
      order.order_items.create!(name: "Item #{status}", unit_price_cents: item_price, quantity: item_qty)
      order.create_shipment!(shipment_attrs(frete))
      order
    end

    def build_carrier(item_price:)
      carrier = @user.orders.create!(subtotal_cents: item_price, total_cents: item_price + 1184, status: "awaiting_payment")
      carrier.order_items.create!(name: "Novo item", unit_price_cents: item_price, quantity: 1)
      carrier.create_shipment!(shipment_attrs(1184))
      carrier.confirm_payment!
      carrier
    end

    def shipment_attrs(frete)
      {
        service: "pac", shipping_cents: frete, weight_grams: 250,
        height_cm: 4, width_cm: 16, length_cm: 24,
        receiver_name: "Master", receiver_cpf: "39053344705", zip: "04534003",
        street: "Rua", number: "1", neighborhood: "Itaim", city: "São Paulo", state: "SP"
      }
    end

    test "folds carrier + absorbed items into the master and recomputes its totals" do
      Orders::Merge.call(order_merge: @plan, actor: @user)

      @master.reload
      assert_equal 3, @master.order_items.count
      assert_equal 10_000 + 10_000 + 3_000, @master.subtotal_cents
      assert_equal 2384, @master.shipment.shipping_cents
      assert_equal 508, @master.shipment.weight_grams
      assert_equal 23_000 + 2384, @master.total_cents
      assert @master.payment_confirmed?, "master keeps its own status"
    end

    test "marks the absorbed order and carrier merged, linked to the master, shipments gone" do
      Orders::Merge.call(order_merge: @plan, actor: @user)

      [ @absorbed, @carrier ].each do |order|
        order.reload
        assert order.merged?
        assert_equal @master, order.merged_into
        assert_nil order.shipment
        assert_empty order.order_items
      end
      assert @plan.reload.executed_at.present?
    end

    test "carries the carrier and absorbed observations onto the master, labelled by order" do
      @master.update_column(:observation, "Nota do master")
      @absorbed.update_column(:observation, "Nota do absorvido")
      @carrier.update_column(:observation, "Nota do carrinho")

      Orders::Merge.call(order_merge: @plan, actor: @user)

      observation = @master.reload.observation
      assert_includes observation, "Nota do master"
      assert_includes observation, "[#{@absorbed.number}] Nota do absorvido"
      assert_includes observation, "[#{@carrier.number}] Nota do carrinho"
    end

    test "leaves the master note untouched when no folded order carries one" do
      @master.update_column(:observation, "Só a nota do master")

      Orders::Merge.call(order_merge: @plan, actor: @user)

      assert_equal "Só a nota do master", @master.reload.observation
    end

    test "is idempotent: a second run makes no further changes" do
      Orders::Merge.call(order_merge: @plan, actor: @user)
      items = @master.reload.order_items.count

      Orders::Merge.call(order_merge: @plan.reload, actor: @user)
      assert_equal items, @master.reload.order_items.count
    end

    test "skips an absorbed order that drifted out of an eligible state" do
      @absorbed.update_column(:status, "in_production")

      Orders::Merge.call(order_merge: @plan, actor: @user)

      @absorbed.reload
      assert @absorbed.in_production?, "drifted order is left untouched"
      assert_not_nil @absorbed.shipment
      assert_equal 1, @absorbed.order_items.count
      assert @carrier.reload.merged?
    end

    test "aborts without changes when the master already has a shipping label" do
      @master.shipment.update_column(:tracking_code, "PG123456789BR")

      Orders::Merge.call(order_merge: @plan, actor: @user)

      assert_not @carrier.reload.merged?
      assert_nil @plan.reload.executed_at
      assert_equal 1, @master.reload.order_items.count
    end

    test "aborts when the master has no shipment to update" do
      @master.shipment.destroy!

      Orders::Merge.call(order_merge: @plan, actor: @user)

      assert_not @carrier.reload.merged?
      assert_nil @plan.reload.executed_at
    end
  end
end
