require "test_helper"

module Admin
  class OrderMergesControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    SERVICES = [ { key: :pac, label: "PAC", eligible: true, price_cents: 2_600, business_days: 7 } ].freeze

    setup do
      @user = User.create!(
        email: "bo-merge-ctrl@example.com", password: "password123",
        full_name: "Cliente Painel", cpf: "39053344705", phone: "11900000000", confirmed_at: 1.day.ago
      )
      @master   = add_order(status: "payment_confirmed", created: 3.days.ago)
      @absorbed = add_order(status: "awaiting_components", created: 2.days.ago)
      @shipped  = add_order(status: "shipped", created: 1.day.ago)
    end

    def add_order(status:, created:)
      order = @user.orders.create!(subtotal_cents: 5_000, total_cents: 6_500)
      order.update_columns(status: status, created_at: created)
      order.order_items.create!(name: "Cartucho", unit_price_cents: 5_000, quantity: 1)
      order.create_shipment!(
        service: "pac", shipping_cents: 1_500, weight_grams: 250,
        receiver_name: "Cliente", receiver_cpf: "39053344705", zip: "01310100",
        street: "Rua das Flores", number: "150", neighborhood: "Centro", city: "São Paulo", state: "SP"
      )
      order
    end

    def with_quote(&block)
      Shipping::Quote.stub(:call, SERVICES, &block)
    end

    test "non-admins are sent to the backoffice login" do
      post admin_order_merge_path(@master), params: { numbers: [ @absorbed.number ] }
      assert_redirected_to admin_login_path
    end

    test "the order page lists the client's other orders split by eligibility" do
      sign_in users(:admin)
      get admin_order_path(@master)

      assert_select "[data-merge-panel] form#merge-form[action=?]", admin_order_merge_path(@master)
      assert_select "[data-merge-row] input[name='numbers[]'][value=?]", @absorbed.number
      assert_select "[data-merge-blocked=?] .mg-why", @shipped.number, text: /Já enviado/
      assert_select "[data-merge-lock]", count: 0
    end

    test "an order whose label is still being bought waits, and says why" do
      busy = add_order(status: "in_production", created: 1.hour.ago)
      busy.shipment.create_shipping_label!(state: :prepost_created)
      sign_in users(:admin)
      get admin_order_path(@master)

      assert_select "[data-merge-blocked=?] .mg-why", busy.number, text: /Etiqueta sendo emitida/
    end

    test "an ineligible master shows why it is locked and offers nothing to pick" do
      @master.update_column(:status, "delivered")
      sign_in users(:admin)
      get admin_order_path(@master)

      assert_select "[data-merge-lock]", text: /o pedido já foi entregue/
      assert_select "[data-merge-row]", count: 0
      assert_select "[data-merge-blocked=?] .mg-why", @absorbed.number, text: /Não elegível/
      assert_select "[data-merge-open]", count: 0
    end

    test "a client with no other order sees the empty state" do
      solo = User.create!(
        email: "solo@example.com", password: "password123",
        full_name: "Cliente Solo", cpf: "52998224725", phone: "11900000001", confirmed_at: 1.day.ago
      )
      @master.update_column(:user_id, solo.id)
      sign_in users(:admin)
      get admin_order_path(@master)

      assert_select ".mg-empty", text: /não tem outros pedidos/
    end

    test "preview renders the confirm modal for the picked orders" do
      sign_in users(:admin)
      with_quote { post admin_order_merge_preview_path(@master), params: { numbers: [ @absorbed.number ] } }

      assert_response :success
      assert_select "[data-merge-overlay] h3", text: "Mesclar 1 pedido em #{@master.number}?"
      assert_select "button[type=submit][form=merge-form][data-merge-confirm]"
      assert_select "[data-merge-shipping]", text: "R$ 26,00"
    end

    test "preview explains a refusal instead of offering the confirm button" do
      sign_in users(:admin)
      post admin_order_merge_preview_path(@master), params: { numbers: [ @shipped.number ] }

      assert_select "[data-merge-error]", text: /deixou de ser elegível/
      assert_select "[data-merge-confirm]", count: 0
    end

    test "create merges the orders and shows the result on the master" do
      sign_in users(:admin)
      with_quote { post admin_order_merge_path(@master), params: { numbers: [ @absorbed.number ] } }

      assert_redirected_to admin_order_path(@master)
      assert_match "1 pedido mesclado em #{@master.number}", flash[:notice]
      assert @absorbed.reload.merged?

      follow_redirect!
      assert_select ".hist-body .note", text: "Mesclou #{@absorbed.number}"
      assert_select "[data-merge-blocked=?] .mg-why", @absorbed.number, text: /Mesclado neste pedido/
    end

    test "a master whose label was voided by the merge shows no label in progress" do
      @master.update_column(:status, "label_issued")
      @master.shipment.create_shipping_label!(state: :ready, filename: "r.pdf", pdf_base64: "x")
      sign_in users(:admin)
      with_quote { post admin_order_merge_path(@master), params: { numbers: [ @absorbed.number ] } }
      follow_redirect!

      assert_select ".od-head-num .pill", text: "Aguardando componentes"
      assert_select ".headpill-proc", count: 0
      assert_select "[data-merge-lock]", count: 0
    end

    test "create reports a refusal as an alert" do
      sign_in users(:admin)
      post admin_order_merge_path(@master), params: { numbers: [] }

      assert_redirected_to admin_order_path(@master)
      assert_equal "Selecione ao menos um pedido para mesclar.", flash[:alert]
    end

    test "a paid checkout carrier whose merge never ran is flagged on its page" do
      carrier = add_order(status: "payment_confirmed", created: 1.hour.ago)
      OrderMerge.create!(
        carrier_order: carrier, master_order: @master, absorbed_order_ids: [],
        combined_weight_grams: 500, combined_service: "pac", combined_shipping_cents: 2_600, paid_fretes_cents: 1_500
      )
      sign_in users(:admin)
      get admin_order_path(carrier)

      assert_select "[data-merge-stranded] a[href=?]", admin_order_path(@master)
    end
  end
end
