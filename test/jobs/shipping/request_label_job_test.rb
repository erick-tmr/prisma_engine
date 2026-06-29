require "test_helper"

module Shipping
  class RequestLabelJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    BASE = Correios::Api::BASE_URL
    URL = "#{BASE}/prepostagem/v1/prepostagens/rotulo/assincrono/pdf".freeze

    setup do
      @order = orders(:producing)
      @shipment = @order.shipment
      @shipment.update!(pre_post_id: "PR-9")
      @label = @shipment.create_shipping_label!(state: :prepost_confirmed)
    end

    test "requests the label, stores the recibo id and enqueues step 3" do
      stub_request(:post, URL).to_return(
        status: 200, body: { "idRecibo" => "R-42" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      assert_enqueued_with(job: Shipping::DownloadLabelJob, args: [ @order.id ]) do
        Shipping::RequestLabelJob.perform_now(@order.id)
      end

      assert @label.reload.requested?
      assert_equal "R-42", @label.recibo_id
    end

    test "skips the request entirely when the cycle is already claimed (single-flight)" do
      job = Shipping::RequestLabelJob.new(@order.id)
      steal_claim = lambda do |_label|
        @label.update!(state: :requesting)
        true
      end

      job.stub(:applicable?, steal_claim) do
        job.perform_now
      end

      assert @label.reload.requesting?
      assert_nil @label.recibo_id
    end

    test "a transient failure rolls the claim back to prepost_confirmed and retries" do
      stub_request(:post, URL).to_return(status: 503, body: "down")

      assert_enqueued_jobs 1, only: Shipping::RequestLabelJob do
        Shipping::RequestLabelJob.perform_now(@order.id)
      end

      assert @label.reload.prepost_confirmed?
    end

    test "a permanent failure rolls the claim back and records the error" do
      stub_request(:post, URL).to_return(status: 400, body: "bad")

      assert_raises(Correios::Api::Error) { Shipping::RequestLabelJob.perform_now(@order.id) }

      @label.reload
      assert @label.prepost_confirmed?
      assert_equal "correios returned 400: bad", @label.error
    end
  end
end
