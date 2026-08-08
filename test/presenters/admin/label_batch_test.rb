require "test_helper"

module Admin
  class LabelBatchTest < ActiveSupport::TestCase
    test "an empty batch reports nothing and never divides by zero" do
      batch = Admin::LabelBatch.new([])

      assert batch.empty?
      assert_equal 0, batch.total
      assert_equal 0, batch.percent
      assert_not batch.running?
      assert_nil batch.current_number
    end

    test "tallies in flight, settled and failed across the selected orders" do
      queued = orders(:producing)
      queued.shipment.create_shipping_label!(state: :pending)

      failed = orders(:confirmed_paid)
      failed.shipment.create_shipping_label!(state: :prepost_confirmed).record_error!("PPN-320")

      batch = Admin::LabelBatch.for([ queued.reload, failed.reload, orders(:labeled) ])

      assert_equal 3, batch.total
      assert_equal 1, batch.in_flight
      assert_equal 2, batch.settled
      assert_equal 1, batch.failed
      assert_equal 66, batch.percent
      assert batch.running?
    end

    test "names the order Correios is working on right now" do
      running = orders(:producing)
      running.shipment.create_shipping_label!(state: :requested)

      batch = Admin::LabelBatch.for([ orders(:labeled), running.reload ])

      assert_equal running.number, batch.current_number
    end

    test "an order whose label job has not run yet counts as not started, not as done" do
      batch = Admin::LabelBatch.for([ orders(:producing), orders(:confirmed_paid) ])

      assert_equal 2, batch.in_flight
      assert_equal 0, batch.settled
      assert batch.running?, "a batch nothing has started is still running, never concluded"
      assert_equal 0, batch.percent
    end

    test "percent never claims more progress than the batch has made" do
      queued = orders(:producing)
      queued.shipment.create_shipping_label!(state: :pending)

      batch = Admin::LabelBatch.for([ queued.reload, orders(:labeled) ])

      assert_equal 50, batch.percent
      assert batch.running?
    end

    test "a fully settled batch stops running and reads as complete" do
      batch = Admin::LabelBatch.for([ orders(:labeled) ])

      assert_not batch.running?
      assert_equal 100, batch.percent
      assert_nil batch.current_number
    end
  end
end
