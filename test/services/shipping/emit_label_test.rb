require "test_helper"

module Shipping
  class EmitLabelTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup { @order = orders(:producing) }

    test "creates the label on the shipment and enqueues step 1 when none exists yet" do
      assert_enqueued_with(job: Shipping::CreatePrePostagemJob, args: [ { shipment_id: @order.shipment.id } ]) do
        Shipping::EmitLabel.resume(@order.shipment)
      end

      assert @order.shipment.shipping_label.pending?
    end

    test "resumes into the confirmation poll from prepost_created" do
      @order.shipment.create_shipping_label!(state: :prepost_created)

      assert_enqueued_with(job: Shipping::ConfirmPrePostagemJob, args: [ { shipment_id: @order.shipment.id } ]) do
        Shipping::EmitLabel.resume(@order.shipment)
      end
    end

    test "resumes the rótulo request from prepost_confirmed" do
      @order.shipment.create_shipping_label!(state: :prepost_confirmed)

      assert_enqueued_with(job: Shipping::RequestLabelJob, args: [ { shipment_id: @order.shipment.id } ]) do
        Shipping::EmitLabel.resume(@order.shipment)
      end
    end

    test "resumes step 3 from requested" do
      @order.shipment.create_shipping_label!(state: :requested)

      assert_enqueued_with(job: Shipping::DownloadLabelJob, args: [ { shipment_id: @order.shipment.id } ]) do
        Shipping::EmitLabel.resume(@order.shipment)
      end
    end

    test "does nothing once the label is ready" do
      @order.shipment.create_shipping_label!(state: :ready)

      assert_no_enqueued_jobs { Shipping::EmitLabel.resume(@order.shipment) }
    end

    test "ignores a requesting label by default so a live claim is not disturbed" do
      @order.shipment.create_shipping_label!(state: :requesting)

      assert_no_enqueued_jobs { Shipping::EmitLabel.resume(@order.shipment) }
      assert @order.shipment.shipping_label.requesting?
    end

    test "recover rewinds a stuck requesting label and re-requests" do
      label = @order.shipment.create_shipping_label!(state: :requesting)

      assert_enqueued_with(job: Shipping::RequestLabelJob, args: [ { shipment_id: @order.shipment.id } ]) do
        Shipping::EmitLabel.recover(@order.shipment)
      end
      assert label.reload.prepost_confirmed?
    end

    test "recover leaves a healthy label untouched" do
      @order.shipment.create_shipping_label!(state: :prepost_confirmed)

      assert_enqueued_with(job: Shipping::RequestLabelJob, args: [ { shipment_id: @order.shipment.id } ]) do
        Shipping::EmitLabel.recover(@order.shipment)
      end
    end

    test "recover is a no-op when the order has no shipment" do
      order = Order.create!(user: users(:confirmed), subtotal_cents: 1_000, total_cents: 1_000)

      assert_no_enqueued_jobs { Shipping::EmitLabel.recover(order.shipment) }
    end

    test "does nothing when the order has no shipment" do
      order = Order.create!(user: users(:confirmed), subtotal_cents: 1_000, total_cents: 1_000)

      assert_no_enqueued_jobs { Shipping::EmitLabel.resume(order.shipment) }
    end

    test "adopts a label another caller created between our read and our write" do
      order = orders(:awaiting)
      shipment = order.shipment
      assert_nil shipment.shipping_label

      ShippingLabel.create!(shipment_id: shipment.id, state: :prepost_confirmed)

      assert_enqueued_with(job: Shipping::RequestLabelJob, args: [ { shipment_id: shipment.id } ]) do
        Shipping::EmitLabel.resume(order.shipment)
      end
      assert_equal 1, ShippingLabel.where(shipment_id: shipment.id).count
    end

    test "restart clears a recorded failure and resumes from the persisted step" do
      label = @order.shipment.create_shipping_label!(state: :prepost_confirmed)
      label.reset_for_relabel!
      label.record_error!("PPN-295 rótulo não gerado")

      assert_enqueued_with(job: Shipping::RequestLabelJob, args: [ { shipment_id: @order.shipment.id } ]) do
        Shipping::EmitLabel.restart(@order.shipment)
      end

      assert_nil label.reload.error
      assert_equal 0, label.relabel_attempts
    end

    test "restart unsticks a label parked mid-request" do
      label = @order.shipment.create_shipping_label!(state: :prepost_confirmed)
      label.claim_requesting!

      assert_enqueued_with(job: Shipping::RequestLabelJob, args: [ { shipment_id: @order.shipment.id } ]) do
        Shipping::EmitLabel.restart(@order.shipment)
      end

      assert label.reload.prepost_confirmed?
    end

    test "restart starts the saga for an order that never had a label" do
      assert_enqueued_with(job: Shipping::CreatePrePostagemJob, args: [ { shipment_id: @order.shipment.id } ]) do
        Shipping::EmitLabel.restart(@order.shipment)
      end
    end

    test "restart is a no-op when the order has no shipment" do
      order = Order.create!(user: users(:confirmed), subtotal_cents: 1_000, total_cents: 1_000)

      assert_no_enqueued_jobs { Shipping::EmitLabel.restart(order.shipment) }
    end
  end
end
