require "test_helper"

module Shipping
  class ConfirmPrePostagemJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    BASE = Correios::Api::BASE_URL
    CODE = "AD601193771BR".freeze
    URL = "#{BASE}/prepostagem/v2/prepostagens?codigoObjeto=#{CODE}".freeze

    setup do
      @order = orders(:producing)
      @shipment = @order.shipment
      @shipment.update!(tracking_code: CODE)
      @label = @shipment.create_shipping_label!(state: :prepost_created)
    end

    test "confirms the label and enqueues the rótulo request once Pré-postado" do
      stub_status(item(2, "Pré-postado"))

      assert_enqueued_with(job: Shipping::RequestLabelJob, args: [ @order.id ]) do
        Shipping::ConfirmPrePostagemJob.perform_now(@order.id)
      end

      assert @label.reload.prepost_confirmed?
      assert_equal 2, @shipment.reload.correios_status
    end

    test "reschedules the next poll while still Pendente" do
      stub_status(item(7, "Pendente"))

      assert_enqueued_with(job: Shipping::ConfirmPrePostagemJob, args: [ @order.id, 2 ]) do
        Shipping::ConfirmPrePostagemJob.perform_now(@order.id)
      end

      assert @label.reload.prepost_created?
      assert_nil @label.error
    end

    test "records an error once the poll attempts are exhausted" do
      stub_status(item(7, "Pendente"))

      assert_no_enqueued_jobs do
        Shipping::ConfirmPrePostagemJob.perform_now(@order.id, Shipping::PREPOSTAGEM_MAX_POLL_ATTEMPTS)
      end

      assert @label.reload.prepost_created?
      assert_match(/Pendente/, @label.error)
      assert_not_nil @label.errored_at
    end

    test "a transient error reschedules the job and leaves the label untouched" do
      stub_request(:get, URL).to_return(status: 503, body: "unavailable")

      assert_enqueued_jobs 1, only: Shipping::ConfirmPrePostagemJob do
        Shipping::ConfirmPrePostagemJob.perform_now(@order.id)
      end

      assert @label.reload.prepost_created?
      assert_nil @label.error
    end

    test "a permanent error is recorded on the label and re-raised" do
      stub_request(:get, URL).to_return(status: 400, body: "bad request")

      assert_raises(Correios::Api::Error) do
        Shipping::ConfirmPrePostagemJob.perform_now(@order.id)
      end

      assert @label.reload.prepost_created?
      assert_equal "correios returned 400: bad request", @label.error
    end

    test "no-ops when the order does not exist" do
      assert_nothing_raised { Shipping::ConfirmPrePostagemJob.perform_now(-1) }
    end

    test "no-ops when the order has no shipment" do
      order = Order.create!(user: users(:confirmed), subtotal_cents: 1_000, total_cents: 1_000)

      assert_no_enqueued_jobs { Shipping::ConfirmPrePostagemJob.perform_now(order.id) }
    end

    test "no-ops when the label is not awaiting confirmation" do
      @label.update!(state: :prepost_confirmed)

      assert_no_enqueued_jobs { Shipping::ConfirmPrePostagemJob.perform_now(@order.id) }
    end

    private

    def stub_status(item)
      stub_request(:get, URL).to_return(
        status: 200, body: { "itens" => [ item ] }.to_json, headers: { "Content-Type" => "application/json" }
      )
    end

    def item(status, label)
      {
        "codigoObjeto" => CODE,
        "statusAtual" => status,
        "descStatusAtual" => label,
        "dataHoraStatusAtual" => "2026-06-22T20:00:34.711579"
      }
    end
  end
end
