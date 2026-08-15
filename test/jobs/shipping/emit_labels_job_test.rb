require "test_helper"

module Shipping
  class EmitLabelsJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    test "hands each existing order to its own job and skips missing ids" do
      order = orders(:producing)

      assert_enqueued_with(job: Shipping::EmitLabelJob, args: [ order.id ]) do
        Shipping::EmitLabelsJob.perform_now([ order.id, -1 ])
      end

      assert_enqueued_jobs 1, only: Shipping::EmitLabelJob
    end

    test "an order that blows up cannot rob the rest of the batch" do
      first, second = orders(:producing), orders(:awaiting)

      Shipping::EmitLabel.stub(:resume, ->(_shipment) { raise "boom" }) do
        assert_nothing_raised { Shipping::EmitLabelsJob.perform_now([ first.id, second.id ]) }
      end

      assert_enqueued_jobs 2, only: Shipping::EmitLabelJob
    end
  end
end
