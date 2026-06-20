require "test_helper"

module Shipping
  class EmitLabelsJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    test "resumes label emission for each existing order and skips missing ids" do
      order = orders(:producing)

      assert_enqueued_with(job: Shipping::CreatePrePostagemJob, args: [ order.id ]) do
        Shipping::EmitLabelsJob.perform_now([ order.id, -1 ])
      end

      assert order.reload.shipping_label.pending?
    end
  end
end
