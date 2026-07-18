require "test_helper"

class OrderMergeTest < ActiveSupport::TestCase
  def build_merge(overrides = {})
    OrderMerge.new({
      carrier_order:           orders(:awaiting),
      master_order:            orders(:confirmed_paid),
      absorbed_order_ids:      [ orders(:producing).id ],
      combined_weight_grams:   500,
      combined_service:        "pac",
      combined_shipping_cents: 3200,
      paid_fretes_cents:       2990
    }.merge(overrides))
  end

  test "a fully-populated record is valid and pending" do
    merge = build_merge
    assert merge.valid?
    assert merge.pending?
  end

  test "belongs to the carrier and master orders" do
    merge = build_merge
    assert_equal orders(:awaiting), merge.carrier_order
    assert_equal orders(:confirmed_paid), merge.master_order
  end

  test "absorbed_orders resolves the stored ids" do
    merge = build_merge(absorbed_order_ids: [ orders(:producing).id, orders(:delivered).id ])
    assert_equal [ orders(:producing), orders(:delivered) ].map(&:id).sort, merge.absorbed_orders.pluck(:id).sort
  end

  test "pending? flips once executed_at is set" do
    merge = build_merge(executed_at: Time.current)
    assert_not merge.pending?
  end

  test "rejects an unknown combined_service" do
    assert_not build_merge(combined_service: "carrier_pigeon").valid?
  end

  test "rejects negative money and weight" do
    assert_not build_merge(combined_shipping_cents: -1).valid?
    assert_not build_merge(paid_fretes_cents: -1).valid?
    assert_not build_merge(combined_weight_grams: -1).valid?
  end
end
