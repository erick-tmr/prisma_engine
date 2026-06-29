require "test_helper"

module Shipping
  class EmitLabelTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup { @order = orders(:producing) }

    test "creates the label on the shipment and enqueues step 1 when none exists yet" do
      assert_enqueued_with(job: Shipping::CreatePrePostagemJob, args: [ @order.id ]) do
        Shipping::EmitLabel.resume(@order)
      end

      assert @order.shipment.shipping_label.pending?
    end

    test "resumes into the confirmation poll from prepost_created" do
      @order.shipment.create_shipping_label!(state: :prepost_created)

      assert_enqueued_with(job: Shipping::ConfirmPrePostagemJob, args: [ @order.id ]) do
        Shipping::EmitLabel.resume(@order)
      end
    end

    test "resumes the rótulo request from prepost_confirmed" do
      @order.shipment.create_shipping_label!(state: :prepost_confirmed)

      assert_enqueued_with(job: Shipping::RequestLabelJob, args: [ @order.id ]) do
        Shipping::EmitLabel.resume(@order)
      end
    end

    test "resumes step 3 from requested" do
      @order.shipment.create_shipping_label!(state: :requested)

      assert_enqueued_with(job: Shipping::DownloadLabelJob, args: [ @order.id ]) do
        Shipping::EmitLabel.resume(@order)
      end
    end

    test "does nothing once the label is ready" do
      @order.shipment.create_shipping_label!(state: :ready)

      assert_no_enqueued_jobs { Shipping::EmitLabel.resume(@order) }
    end

    test "ignores a requesting label by default so a live claim is not disturbed" do
      @order.shipment.create_shipping_label!(state: :requesting)

      assert_no_enqueued_jobs { Shipping::EmitLabel.resume(@order) }
      assert @order.shipment.shipping_label.requesting?
    end

    test "recover rewinds a stuck requesting label and re-requests" do
      label = @order.shipment.create_shipping_label!(state: :requesting)

      assert_enqueued_with(job: Shipping::RequestLabelJob, args: [ @order.id ]) do
        Shipping::EmitLabel.recover(@order)
      end
      assert label.reload.prepost_confirmed?
    end

    test "recover leaves a healthy label untouched" do
      @order.shipment.create_shipping_label!(state: :prepost_confirmed)

      assert_enqueued_with(job: Shipping::RequestLabelJob, args: [ @order.id ]) do
        Shipping::EmitLabel.recover(@order)
      end
    end

    test "recover is a no-op when the order has no shipment" do
      order = Order.create!(user: users(:confirmed), subtotal_cents: 1_000, total_cents: 1_000)

      assert_no_enqueued_jobs { Shipping::EmitLabel.recover(order) }
    end

    test "does nothing when the order has no shipment" do
      order = Order.create!(user: users(:confirmed), subtotal_cents: 1_000, total_cents: 1_000)

      assert_no_enqueued_jobs { Shipping::EmitLabel.resume(order) }
    end
  end
end
