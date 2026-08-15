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

      assert_enqueued_with(job: Shipping::RequestLabelJob, args: [ { shipment_id: @shipment.id } ]) do
        Shipping::ConfirmPrePostagemJob.perform_now(shipment_id: @shipment.id)
      end

      assert @label.reload.prepost_confirmed?
      assert_equal 2, @shipment.reload.correios_status
    end

    test "reschedules the next poll while still Pendente" do
      stub_status(item(7, "Pendente"))

      assert_enqueued_with(job: Shipping::ConfirmPrePostagemJob, args: [ { shipment_id: @shipment.id, attempt: 2 } ]) do
        Shipping::ConfirmPrePostagemJob.perform_now(shipment_id: @shipment.id)
      end

      assert @label.reload.prepost_created?
      assert_nil @label.error
    end

    test "backs off exponentially between polls, capped at the ceiling" do
      stub_status(item(7, "Pendente"))
      expected = { 1 => 10.seconds, 2 => 20.seconds, 3 => 40.seconds, 4 => 80.seconds, 5 => 2.minutes, 12 => 2.minutes }

      freeze_time do
        expected.each do |attempt, delay|
          assert_enqueued_with(job: Shipping::ConfirmPrePostagemJob, args: [ { shipment_id: @shipment.id, attempt: attempt + 1 } ], at: delay.from_now) do
            Shipping::ConfirmPrePostagemJob.perform_now(shipment_id: @shipment.id, attempt: attempt)
          end
        end
      end
    end

    test "the whole poll window outlasts a slow Correios promotion" do
      total = (1...Shipping::PREPOSTAGEM_MAX_POLL_ATTEMPTS).sum do |attempt|
        [ Shipping::PREPOSTAGEM_POLL_BASE_DELAY * (2**(attempt - 1)), Shipping::PREPOSTAGEM_POLL_MAX_DELAY ].min
      end

      assert_operator Shipping::PREPOSTAGEM_INITIAL_DELAY + total, :>, 20.minutes
    end

    test "records an error once the poll attempts are exhausted" do
      stub_status(item(7, "Pendente"))

      assert_no_enqueued_jobs do
        Shipping::ConfirmPrePostagemJob.perform_now(shipment_id: @shipment.id, attempt: Shipping::PREPOSTAGEM_MAX_POLL_ATTEMPTS)
      end

      assert @label.reload.prepost_created?
      assert_match(/Pendente/, @label.error)
      assert_not_nil @label.errored_at
    end

    test "a transient error reschedules the job and leaves the label untouched" do
      stub_request(:get, URL).to_return(status: 503, body: "unavailable")

      assert_enqueued_jobs 1, only: Shipping::ConfirmPrePostagemJob do
        Shipping::ConfirmPrePostagemJob.perform_now(shipment_id: @shipment.id)
      end

      assert @label.reload.prepost_created?
      assert_nil @label.error
    end

    test "a permanent error is recorded on the label and re-raised" do
      stub_request(:get, URL).to_return(status: 400, body: "bad request")

      assert_raises(Correios::Api::Error) do
        Shipping::ConfirmPrePostagemJob.perform_now(shipment_id: @shipment.id)
      end

      assert @label.reload.prepost_created?
      assert_equal "correios returned 400: bad request", @label.error
    end

    test "no-ops when the shipment does not exist" do
      assert_nothing_raised { Shipping::ConfirmPrePostagemJob.perform_now(shipment_id: -1) }
    end

    test "no-ops when the shipment has no label yet" do
      @label.destroy!

      assert_no_enqueued_jobs { Shipping::ConfirmPrePostagemJob.perform_now(shipment_id: @shipment.id) }
    end

    test "no-ops when the label is not awaiting confirmation" do
      @label.update!(state: :prepost_confirmed)

      assert_no_enqueued_jobs { Shipping::ConfirmPrePostagemJob.perform_now(shipment_id: @shipment.id) }
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
