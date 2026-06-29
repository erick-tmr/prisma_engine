require "test_helper"

module Shipping
  class RecoverStuckLabelRequestsJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup { @order = orders(:producing) }

    test "recovers a label stranded in requesting past the threshold" do
      label = @order.shipment.create_shipping_label!(state: :requesting)
      label.update_columns(requesting_at: 11.minutes.ago)

      assert_enqueued_with(job: Shipping::RequestLabelJob, args: [ @order.id ]) do
        Shipping::RecoverStuckLabelRequestsJob.perform_now
      end
      assert label.reload.prepost_confirmed?
    end

    test "leaves a recently claimed label alone" do
      label = @order.shipment.create_shipping_label!(state: :requesting)
      label.update_columns(requesting_at: 1.minute.ago)

      assert_no_enqueued_jobs { Shipping::RecoverStuckLabelRequestsJob.perform_now }
      assert label.reload.requesting?
    end
  end
end
