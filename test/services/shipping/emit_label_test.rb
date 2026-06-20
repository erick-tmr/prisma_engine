require "test_helper"

module Shipping
  class EmitLabelTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    test "creates the label and enqueues step 1 when none exists yet" do
      order = orders(:producing)

      assert_enqueued_with(job: Shipping::CreatePrePostagemJob, args: [ order.id ]) do
        Shipping::EmitLabel.resume(order)
      end

      assert order.reload.shipping_label.pending?
    end

    test "resumes step 2 from prepost_created" do
      order = orders(:producing)
      order.create_shipping_label!(state: :prepost_created)

      assert_enqueued_with(job: Shipping::RequestLabelJob, args: [ order.id ]) do
        Shipping::EmitLabel.resume(order)
      end
    end

    test "resumes step 3 from requested" do
      order = orders(:producing)
      order.create_shipping_label!(state: :requested)

      assert_enqueued_with(job: Shipping::DownloadLabelJob, args: [ order.id ]) do
        Shipping::EmitLabel.resume(order)
      end
    end

    test "does nothing once the label is ready" do
      order = orders(:producing)
      order.create_shipping_label!(state: :ready)

      assert_no_enqueued_jobs { Shipping::EmitLabel.resume(order) }
    end
  end
end
