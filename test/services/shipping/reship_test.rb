require "test_helper"

module Shipping
  class ReshipTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper
    include ActionMailer::TestHelper

    DCE_URL = "#{Correios::Api::BASE_URL}/prepostagem/v1/prepostagens/dce/dace/impressao".freeze

    setup do
      @order = orders(:delivered)
      @outbound = @order.shipment
      @outbound.update_columns(created_at: 3.days.ago, receiver_obs: "Deixar na portaria", delivery_business_days: 6)
      @order.update_columns(status: "returned")
      @order.status_changes.create!(from_status: "delivered", to_status: "returned", automatic: true)
    end

    test "supersedes the despatch that came back and opens a new one with the same snapshot" do
      result = Shipping::Reship.call(order: @order)

      assert result.success?
      assert @outbound.reload.superseded?
      shipment = @order.reload.shipment
      assert_equal result.shipment, shipment
      assert shipment.outbound?
      assert_nil shipment.tracking_code
      assert shipment.tracking_pending?
      assert_equal @outbound.slice(*Shipping::Reship::CLONED), shipment.slice(*Shipping::Reship::CLONED)
      assert_equal [ @outbound ], @order.past_shipments
    end

    SERVICES = Shipping::SERVICES.keys.map(&:to_s).freeze
    PICKS = [ nil, "", *SERVICES ].freeze
    LEGS = %w[bounce customer_return].freeze

    SERVICES.product(PICKS, LEGS).each do |paid, pick, leg|
      test "paid #{paid}, operator picks #{pick.inspect}, back by #{leg}" do
        @outbound.update_columns(service: paid)
        if leg == "customer_return"
          return_service = (SERVICES - [ paid ]).first
          Shipment.create!(order: @order, direction: :inbound, service: return_service, created_at: 2.days.ago,
                           **@outbound.slice(*Shipping::StartReturn::CLONED).symbolize_keys)
        end
        expected = pick.presence || Shipping::DEFAULT_RETURN_SERVICE

        result = Shipping::Reship.call(order: @order, service: pick)

        assert result.success?
        shipment = @order.reload.shipment
        assert_equal expected, shipment.service
        if expected == paid
          assert_equal 6, shipment.delivery_business_days
        else
          assert_nil shipment.delivery_business_days
        end
        assert_equal @outbound.shipping_cents, shipment.shipping_cents
        assert_equal @outbound.zip, shipment.zip
        assert_nil @order.return_shipment
      end
    end

    test "a service Correios does not sell us is refused before anything is touched" do
      result = Shipping::Reship.call(order: @order, service: "carta")

      assert_equal :invalid_service, result.error
      assert_not @outbound.reload.superseded?
    end

    test "starts the label saga on the new despatch" do
      Shipping::Reship.call(order: @order)

      shipment = @order.reload.shipment
      assert shipment.shipping_label.pending?
      assert_enqueued_with(job: Shipping::CreatePrePostagemJob, args: [ { shipment_id: shipment.id } ])
    end

    test "leaves the order returned until the new label exists, so nobody is e-mailed yet" do
      assert_no_difference -> { @order.status_changes.count } do
        assert_no_enqueued_emails { Shipping::Reship.call(order: @order) }
      end

      assert @order.reload.returned?
    end

    test "a second click while the new label is being bought is refused" do
      Shipping::Reship.call(order: @order)

      assert_no_difference -> { Shipment.count } do
        result = Shipping::Reship.call(order: @order.reload)

        assert_not result.success?
        assert_equal :not_reshippable, result.error
      end
    end

    test "retires the customer's return leg so a later return can open a new one" do
      inbound = Shipment.create!(order: @order, direction: :inbound, service: "pac", created_at: 2.days.ago,
                                 **@outbound.slice(*Shipping::StartReturn::CLONED).symbolize_keys)

      Shipping::Reship.call(order: @order)

      assert inbound.reload.superseded?
      assert_nil @order.reload.return_shipment
      assert_equal @order.shipment, @order.tracked_shipment
      assert_equal [ @outbound, inbound ].to_set, @order.past_shipments.to_set
    end

    test "refuses an order that is not returned" do
      @order.update_columns(status: "delivered")

      result = Shipping::Reship.call(order: @order)

      assert_equal :not_reshippable, result.error
      assert_not @outbound.reload.superseded?
    end

    test "refuses a returned order without a despatch" do
      @outbound.destroy!

      assert_not Shipping::Reship.reshippable?(@order.reload)
    end

    test "refuses a returned order with no recorded handback" do
      @order.status_changes.where(to_status: "returned").delete_all

      assert_not Shipping::Reship.reshippable?(@order)
    end

    test "the new label moves the order to label_issued and e-mails the customer the new code" do
      Shipping::Reship.call(order: @order)
      shipment = @order.reload.shipment
      shipment.update!(pre_post_id: "PR-RESHIP", tracking_code: "AD123456789BR")
      shipment.shipping_label.store_label!(filename: "etiqueta.pdf", pdf: "JVBERi0=")
      stub_request(:post, DCE_URL).to_return(
        status: 200, headers: { "Content-Type" => "application/json" },
        body: { "objetos" => [ "PR-RESHIP" ], "dados" => Base64.strict_encode64("%PDF-1.4 dace") }.to_json
      )

      assert_enqueued_email_with OrderMailer, :label_issued, args: [ @order ] do
        Shipping::DownloadDceJob.perform_now(shipment_id: shipment.id)
      end

      assert @order.reload.label_issued?
      assert_equal "AD123456789BR", @order.shipment.tracking_code
    end
  end
end
