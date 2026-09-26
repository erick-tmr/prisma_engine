require "test_helper"

module Orders
  class MergeTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper
    include ActionMailer::TestHelper

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

    def backoffice_plan
      OrderMerge.create!(
        master_order: @master, absorbed_order_ids: [ @absorbed.id ],
        combined_weight_grams: 508, combined_service: "pac",
        combined_shipping_cents: 2384, paid_fretes_cents: 1200
      )
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
      assert @master.awaiting_components?, "master takes the most blocked participant's status"
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

    test "aborts when the master was cancelled between the quote and the payment" do
      @master.cancel!

      Orders::Merge.call(order_merge: @plan, actor: @user)

      assert_not @carrier.reload.merged?
      assert_nil @plan.reload.executed_at
      assert @master.reload.cancelled?
    end

    test "a checkout merge never folds into a master already in production" do
      @master.update_column(:status, "in_production")

      Orders::Merge.call(order_merge: @plan, actor: @user)

      assert_not @carrier.reload.merged?
      assert_equal 1, @master.reload.order_items.count
    end

    test "records the merge on the master's history without e-mailing the customer" do
      @absorbed.update_column(:status, "payment_confirmed")

      assert_no_enqueued_emails do
        Orders::Merge.call(order_merge: @plan, actor: @user)
      end

      change = @master.status_changes.find_by!(order_merge: @plan)
      assert_equal %w[payment_confirmed payment_confirmed], [ change.from_status, change.to_status ]
      assert change.automatic
      assert @master.reload.payment_confirmed?
    end

    test "a production issue on an absorbed order carries over to the master" do
      @absorbed.update_column(:status, "production_issue")

      Orders::Merge.call(order_merge: @plan, actor: @user)

      assert @master.reload.production_issue?
    end

    test "missing components outrank a production issue, since the parcel still waits for stock" do
      @master.update_column(:status, "production_issue")

      Orders::Merge.call(order_merge: @plan, actor: @user)

      assert @master.reload.awaiting_components?
    end

    test "a backoffice merge folds an order already in production and settles on the least advanced status" do
      operator = users(:admin)
      @master.update_column(:status, "in_production")
      @absorbed.update_column(:status, "payment_confirmed")
      plan = backoffice_plan

      Orders::Merge.call(order_merge: plan, actor: operator)

      @master.reload
      assert @master.payment_confirmed?
      assert @absorbed.reload.merged?
      assert_equal 2, @master.order_items.count
      change = @master.status_changes.find_by!(order_merge: plan)
      assert_equal operator, change.actor
      assert_not change.automatic
      assert_not @absorbed.status_changes.find_by!(to_status: "merged").automatic
    end

    test "a backoffice merge into a label_issued master drops its label and returns it to production" do
      @absorbed.update_column(:status, "in_production")
      @master.update_column(:status, "label_issued")
      @master.shipment.update!(tracking_code: "AA123456789BR", pre_post_id: "PRE-1")
      @master.shipment.create_shipping_label!(state: :ready, recibo_id: "R-1", filename: "r.pdf", pdf_base64: "x")

      assert_no_enqueued_jobs(only: Shipping::CreatePrePostagemJob) do
        Orders::Merge.call(order_merge: backoffice_plan, actor: users(:admin))
      end

      @master.reload
      assert @master.in_production?
      assert_nil @master.shipment.tracking_code
      assert_nil @master.shipment.pre_post_id
      assert_nil @master.shipment.shipping_label, "no label left behind to read as queued"
      assert Orders::MergeEligibility.for(@master, origin: :backoffice).ok?
    end

    test "a backoffice merge absorbs a label_issued order and drops its shipment" do
      @absorbed.update_column(:status, "label_issued")
      @absorbed.shipment.update!(tracking_code: "AB123456789BR")
      @absorbed.shipment.create_shipping_label!(state: :ready)

      Orders::Merge.call(order_merge: backoffice_plan, actor: users(:admin))

      assert @absorbed.reload.merged?
      assert_nil @absorbed.shipment
      assert @master.reload.payment_confirmed?
    end

    test "a backoffice merge skips an absorbed order whose label is still being bought" do
      @absorbed.update_column(:status, "in_production")
      @absorbed.shipment.create_shipping_label!(state: :prepost_created)

      Orders::Merge.call(order_merge: backoffice_plan, actor: users(:admin))

      assert @absorbed.reload.in_production?
      assert_not_nil @absorbed.shipment
    end

    test "aborts when the master has no shipment to update" do
      @master.shipment.destroy!

      Orders::Merge.call(order_merge: @plan, actor: @user)

      assert_not @carrier.reload.merged?
      assert_nil @plan.reload.executed_at
    end
  end
end
