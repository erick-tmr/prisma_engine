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
  end
end
