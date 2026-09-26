require "test_helper"

module Admin
  class MergeOrdersTest < ActiveSupport::TestCase
    SERVICES = [
      { key: :mini_envios, label: "Mini Envios", eligible: false },
      { key: :pac, label: "PAC", eligible: true, price_cents: 2_600, business_days: 7 },
      { key: :sedex, label: "SEDEX", eligible: true, price_cents: 4_100, business_days: 2 }
    ].freeze

    setup do
      @user = User.create!(
        email: "bo-merge@example.com", password: "password123",
        full_name: "Cliente Mesclado", cpf: "39053344705", phone: "11900000000", confirmed_at: 1.day.ago
      )
      @master = add_order(status: "in_production", frete: 1_900, price: 10_000, created: 3.days.ago)
      @first  = add_order(status: "payment_confirmed", frete: 1_500, price: 4_000, created: 2.days.ago)
      @second = add_order(status: "awaiting_components", frete: 1_700, price: 6_000, created: 1.day.ago)
    end

    def add_order(status:, frete:, price:, created:, street: "Rua das Flores")
      order = @user.orders.create!(subtotal_cents: price, total_cents: price + frete)
      order.update_columns(status: status, created_at: created)
      order.order_items.create!(name: "Cartucho #{status}", unit_price_cents: price, quantity: 1)
      order.create_shipment!(
        service: "mini_envios", shipping_cents: frete, weight_grams: 250,
        receiver_name: "Cliente", receiver_cpf: "39053344705", zip: "01310100",
        street: street, number: "150", neighborhood: "Centro", city: "São Paulo", state: "SP"
      )
      order
    end

    def merger(numbers = [ @first.number, @second.number ], master: @master)
      MergeOrders.new(master: master.reload, numbers: numbers)
    end

    def with_quote(services = SERVICES, &block)
      Shipping::Quote.stub(:call, services, &block)
    end

    test "previews the combined parcel without charging the customer anything new" do
      result = with_quote { merger.preview }

      assert result.success?
      preview = result.preview
      assert_equal [ @first, @second ], preview.absorbed
      assert_equal "pac", preview.service
      assert_equal 2_600, preview.combined_shipping_cents
      assert_equal 2_600, preview.shipping_cents
      assert_equal 20_000, preview.subtotal_cents
      assert_equal 22_600, preview.total_cents
      assert_equal 3, preview.item_count
      assert_equal "awaiting_components", preview.settled_status
      assert_empty preview.address_mismatches
      assert_empty preview.voided_labels
    end

    test "keeps the master's frete when it already paid more than the combined quote" do
      @master.shipment.update!(shipping_cents: 3_000)

      assert_equal 3_000, with_quote { merger.preview }.preview.shipping_cents
    end

    test "flags an absorbed order that ships somewhere else, and every label the merge voids" do
      elsewhere = add_order(status: "label_issued", frete: 1_500, price: 1_000, created: 1.hour.ago, street: "Av. Paulista")
      elsewhere.shipment.create_shipping_label!(state: :ready)
      @master.shipment.create_shipping_label!(state: :ready)

      preview = with_quote { merger([ elsewhere.number ]).preview }.preview

      assert_equal [ elsewhere ], preview.address_mismatches
      assert_equal [ @master, elsewhere ], preview.voided_labels
    end

    test "refuses a master that cannot take a merge" do
      @master.update_column(:status, "shipped")

      assert_equal :master_ineligible, merger.preview.error
    end

    test "asks for at least one order" do
      assert_equal :nothing_selected, merger([ "" ]).preview.error
    end

    test "refuses the whole merge when any picked order is not eligible or not the client's" do
      @second.update_column(:status, "delivered")
      assert_equal :ineligible, merger.preview.error

      stranger = Order.create!(user: users(:confirmed), subtotal_cents: 1_000, total_cents: 1_000)
      assert_equal :ineligible, merger([ @first.number, stranger.number ]).preview.error
    end

    test "reports when Correios has no service for the combined parcel, or is down" do
      assert_equal :shipping_unavailable, with_quote([ SERVICES.first ]) { merger.preview }.error

      Shipping::Quote.stub(:call, ->(**) { raise Correios::Api::Error, "down" }) do
        assert_equal :shipping_error, merger.preview.error
      end
    end

    test "merges into the master, records a carrier-less plan and returns the preview" do
      result = with_quote { merger.call(actor: users(:admin)) }

      assert result.success?
      plan = OrderMerge.find_by!(master_order: @master)
      assert_nil plan.carrier_order_id
      assert_equal :backoffice, plan.origin
      assert_equal [ @first.id, @second.id ], plan.absorbed_order_ids
      assert_equal 1_900 + 1_500 + 1_700, plan.paid_fretes_cents
      assert plan.executed_at

      @master.reload
      assert @master.awaiting_components?
      assert_equal 3, @master.order_items.count
      assert_equal 22_600, @master.total_cents
      assert @first.reload.merged?
    end

    test "writes nothing when the executor declines at the last moment" do
      Orders::Merge.stub(:call, nil) do
        assert_equal :ineligible, with_quote { merger.call(actor: users(:admin)) }.error
      end

      assert_not OrderMerge.exists?(master_order: @master)
    end

    test "returns a preview error without writing anything" do
      assert_equal :nothing_selected, merger([]).call(actor: users(:admin)).error
      assert_not OrderMerge.exists?(master_order: @master)
    end
  end
end
