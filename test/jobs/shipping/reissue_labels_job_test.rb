require "test_helper"

module Shipping
  class ReissueLabelsJobTest < ActiveJob::TestCase
    test "reissues every expired order in the batch" do
      first, second = orders(:labeled), orders(:shipped_order)
      [ first, second ].each do |order|
        order.shipment.update!(pre_post_id: "DEAD-#{order.id}", tracking_code: "AD00000000#{order.id}BR")
        order.shipment.expire_prepost(label: "Etiqueta expirada", at: 1.day.ago)
        order.shipment.save!
      end

      Shipping::ReissueLabelsJob.perform_now([ first.id, second.id ])

      [ first, second ].each do |order|
        assert_nil order.shipment.reload.pre_post_id, order.number
        assert_not order.shipment.label_expired?, order.number
      end
    end

    test "skips an order whose label never expired, so no rotulo is bought twice" do
      order = orders(:labeled)
      order.shipment.update!(pre_post_id: "STILL-GOOD", tracking_code: "AD000000777BR")
      assert_not order.shipment.label_expired?

      Shipping::ReissueLabelsJob.perform_now([ order.id ])

      assert_equal "STILL-GOOD", order.shipment.reload.pre_post_id
    end

    test "ignores ids that no longer resolve to an order" do
      assert_nothing_raised { Shipping::ReissueLabelsJob.perform_now([ -1 ]) }
    end
  end
end
