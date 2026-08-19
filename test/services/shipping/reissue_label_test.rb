require "test_helper"

module Shipping
  class ReissueLabelTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @shipment = shipments(:labeled)
      @shipment.order.update_columns(status: "label_issued")
      @label = @shipment.shipping_label
      @label.update!(state: :ready, recibo_id: "REC-1", filename: "rotulo.pdf", pdf_base64: "JVBER",
                     dce_filename: "dce.pdf", dce_base64: "JVBER", relabel_attempts: 2)
      @shipment.update!(
        pre_post_id: "DEAD-ID", tracking_code: "AD000000001BR", service_code: "03298",
        pre_post_payload: { "id" => "DEAD-ID" }, posting_deadline: 2.days.ago,
        requested_at: 16.days.ago, posted_at: 1.day.ago, tracking_state: :in_transit,
        last_tracking_status: "Etiqueta expirada", last_tracked_at: 1.day.ago
      )
      @shipment.expire_prepost(label: "Etiqueta expirada", at: 1.day.ago)
      @shipment.save!
      @shipment.tracking_events.create!(position: 0, event_code: "FC", event_type: "82",
                                        tracking_code: "AD000000001BR")
    end

    test "clears the dead pre-postagem so the next response is not discarded as a duplicate" do
      assert Shipping::ReissueLabel.call(@shipment)

      @shipment.reload
      assert_nil @shipment.pre_post_id
      assert_nil @shipment.tracking_code
      assert_nil @shipment.service_code
      assert_nil @shipment.posting_deadline
      assert_nil @shipment.requested_at
      assert_empty @shipment.pre_post_payload
    end

    test "clears the tracking read-model the dead label left behind" do
      assert Shipping::ReissueLabel.call(@shipment)

      @shipment.reload
      assert @shipment.tracking_pending?
      assert_nil @shipment.posted_at
      assert_nil @shipment.last_tracking_status
      assert_nil @shipment.last_tracked_at
      assert_nil @shipment.correios_status
      assert_not @shipment.label_expired?
      assert_empty @shipment.tracking_events
    end

    test "drops the void rotulo so it can no longer be printed" do
      assert Shipping::ReissueLabel.call(@shipment)

      @label.reload
      assert @label.pending?
      assert_nil @label.recibo_id
      assert_nil @label.pdf_base64
      assert_nil @label.filename
      assert_nil @label.dce_base64
      assert_equal 0, @label.relabel_attempts
    end

    test "restarts the saga at the pre-postagem step" do
      assert_enqueued_with job: Shipping::CreatePrePostagemJob, args: [ { shipment_id: @shipment.id } ] do
        Shipping::ReissueLabel.call(@shipment)
      end
    end

    test "leaves the order on label_issued, so the customer is not e-mailed again" do
      assert_no_difference -> { @shipment.order.status_changes.count } do
        Shipping::ReissueLabel.call(@shipment)
      end

      assert @shipment.order.reload.label_issued?
    end

    test "refuses a shipment whose label has not expired, so a second click cannot buy twice" do
      Shipping::ReissueLabel.call(@shipment)

      assert_no_enqueued_jobs do
        assert_not Shipping::ReissueLabel.call(@shipment.reload)
      end
    end

    test "refuses a missing shipment" do
      assert_not Shipping::ReissueLabel.call(nil)
    end

    test "a shipment that never got a label row is given one and started from scratch" do
      shipment = shipments(:awaiting)
      shipment.expire_prepost(label: "Etiqueta expirada", at: 1.day.ago)
      shipment.save!

      assert Shipping::ReissueLabel.call(shipment)
      assert shipment.reload.shipping_label.pending?
    end
  end
end
