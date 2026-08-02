require "test_helper"

module Shipping
  class EmitLabelJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    test "resumes label emission for the order" do
      order = orders(:producing)

      assert_enqueued_with(job: Shipping::CreatePrePostagemJob, args: [ order.id ]) do
        Shipping::EmitLabelJob.perform_now(order.id)
      end

      assert order.reload.shipping_label.pending?
    end

    test "does nothing when the order was deleted before the job ran" do
      assert_nothing_raised { Shipping::EmitLabelJob.perform_now(-1) }
    end
  end
end
