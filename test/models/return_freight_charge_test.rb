require "test_helper"

class ReturnFreightChargeTest < ActiveSupport::TestCase
  setup do
    @shipment = Shipment.create!(order: orders(:delivered), direction: :inbound, service: "pac")
  end

  test "a fresh charge is pending until its link runs out" do
    freeze_time do
      charge = ReturnFreightCharge.issue(shipment: @shipment, amount_cents: 1490)

      assert_equal Time.current, charge.created_at
      assert_equal 3.days.from_now, charge.expires_at
      assert charge.pending?
      assert_equal "pending", charge.state

      travel ReturnFreightCharge::TTL - 1.second
      assert charge.pending?

      travel 1.second
      assert charge.expired?
      assert_not charge.pending?
      assert_equal "expired", charge.state
    end
  end

  test "a paid charge is paid for good, never expired" do
    charge = ReturnFreightCharge.issue(shipment: @shipment, amount_cents: 1490, at: 1.week.ago)
    charge.update!(paid_at: 6.days.ago)

    assert charge.paid?
    assert_not charge.expired?
    assert_not charge.pending?
    assert_equal "paid", charge.state
  end

  test "an amount must be a positive integer" do
    charge = @shipment.return_freight_charges.build(amount_cents: 0, expires_at: 1.day.from_now)

    assert_not charge.valid?
    assert charge.errors.of_kind?(:amount_cents, :greater_than)
  end

  test "the shipment's charge is the newest one the store has not voided" do
    ReturnFreightCharge.issue(shipment: @shipment, amount_cents: 1000, at: 5.days.ago)
    newest = ReturnFreightCharge.issue(shipment: @shipment, amount_cents: 1100, at: 1.hour.ago)

    assert_equal newest, @shipment.freight_charge

    @shipment.return_freight_charges.update_all(voided_at: Time.current)
    assert_nil @shipment.freight_charge
  end

  test "freight is settled when the store pays or once the customer has paid" do
    assert @shipment.freight_settled?

    charge = ReturnFreightCharge.issue(shipment: @shipment, amount_cents: 1490)
    assert_not @shipment.freight_settled?

    charge.update!(paid_at: Time.current)
    assert @shipment.freight_settled?
  end

  test "the charges go with the shipment" do
    ReturnFreightCharge.issue(shipment: @shipment, amount_cents: 1490)

    assert_difference -> { ReturnFreightCharge.count }, -1 do
      @shipment.destroy!
    end
  end
end
