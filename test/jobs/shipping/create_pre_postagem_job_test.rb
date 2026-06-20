require "test_helper"

module Shipping
  class CreatePrePostagemJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    BASE = Correios::Api::BASE_URL
    URL = "#{BASE}/prepostagem/v1/prepostagens".freeze

    setup do
      @prev_token = ENV["CORREIOS_CARTAO_API_TOKEN"]
      ENV["CORREIOS_CARTAO_API_TOKEN"] = "test-token"
      @order = orders(:producing)
      @shipment = @order.shipment
    end

    teardown do
      ENV["CORREIOS_CARTAO_API_TOKEN"] = @prev_token
    end

    test "creates the pré-postagem, advances the label and enqueues step 2" do
      label = @shipment.create_shipping_label!
      stub_create

      assert_enqueued_with(job: Shipping::RequestLabelJob, args: [ @order.id ]) do
        Shipping::CreatePrePostagemJob.perform_now(@order.id)
      end

      assert label.reload.prepost_created?
      assert_equal "AD515656026BR", @shipment.reload.tracking_code
    end

    test "no-ops when the order does not exist" do
      assert_nothing_raised { Shipping::CreatePrePostagemJob.perform_now(-1) }
    end

    test "no-ops when the order has no shipment" do
      order = Order.create!(user: users(:confirmed), subtotal_cents: 1_000, total_cents: 1_000)

      assert_no_enqueued_jobs { Shipping::CreatePrePostagemJob.perform_now(order.id) }
    end

    test "no-ops when the shipment has no label yet" do
      assert_no_enqueued_jobs { Shipping::CreatePrePostagemJob.perform_now(@order.id) }
      assert_nil @shipment.reload.shipping_label
    end

    test "no-ops when the label is already past this step" do
      @shipment.create_shipping_label!(state: :prepost_created)

      assert_no_enqueued_jobs { Shipping::CreatePrePostagemJob.perform_now(@order.id) }
    end

    test "a transient error reschedules the job and leaves the label untouched" do
      label = @shipment.create_shipping_label!
      stub_request(:post, URL).to_return(status: 503, body: "unavailable")

      assert_enqueued_jobs 1, only: Shipping::CreatePrePostagemJob do
        Shipping::CreatePrePostagemJob.perform_now(@order.id)
      end

      assert label.reload.pending?
      assert_nil label.error
    end

    test "a permanent error is recorded on the label and re-raised" do
      label = @shipment.create_shipping_label!
      stub_request(:post, URL).to_return(status: 400, body: "bad request")

      assert_raises(Correios::Api::Error) do
        Shipping::CreatePrePostagemJob.perform_now(@order.id)
      end

      assert label.reload.pending?
      assert_equal "correios returned 400: bad request", label.error
      assert_not_nil label.errored_at
    end

    private

    def stub_create
      stub_request(:post, URL).to_return(
        status: 201, body: response_body, headers: { "Content-Type" => "application/json" }
      )
    end

    def response_body
      {
        "id" => "PR-1",
        "codigoObjeto" => "AD515656026BR",
        "codigoServico" => "03298",
        "statusAtual" => 1,
        "descStatusAtual" => "Pré-atendido",
        "dataHora" => "2026-06-20T10:00:00",
        "prazoPostagem" => "2026-07-04T23:59:59"
      }.to_json
    end
  end
end
