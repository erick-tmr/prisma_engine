require "test_helper"

class StoreSettingTest < ActiveSupport::TestCase
  test "current returns the existing singleton row" do
    assert_equal store_settings(:default), StoreSetting.current
  end

  test "current creates the row with the default handling fee when none exists" do
    StoreSetting.delete_all

    setting = StoreSetting.current

    assert setting.persisted?
    assert_equal 300, setting.handling_fee_cents
  end

  test "requires a non-negative integer handling fee" do
    setting = store_settings(:default)

    setting.handling_fee_cents = nil
    assert_not setting.valid?

    setting.handling_fee_cents = -1
    assert_not setting.valid?

    setting.handling_fee_cents = 0
    assert setting.valid?
  end

  test "black friday is off without a window" do
    setting = store_settings(:default)

    assert_not setting.black_friday?
    assert_equal :disabled, setting.black_friday_status
  end

  test "black friday runs from its start up to, not including, its end" do
    setting = store_settings(:default)
    starts = Time.zone.parse("2026-11-27 00:00")
    ends = Time.zone.parse("2026-12-01 00:00")
    setting.update!(black_friday_starts_at: starts, black_friday_ends_at: ends)

    assert_not setting.black_friday?(starts - 1.second)
    assert_equal :scheduled, setting.black_friday_status(starts - 1.second)
    assert setting.black_friday?(starts)
    assert_equal :active_until, setting.black_friday_status(starts)
    assert_not setting.black_friday?(ends)
    assert_equal :ended, setting.black_friday_status(ends)
  end

  test "black friday without an end stays on until turned off" do
    setting = store_settings(:default)
    setting.update!(black_friday_starts_at: 1.day.ago)

    assert setting.black_friday?(1.year.from_now)
    assert_equal :active, setting.black_friday_status

    setting.turn_off_black_friday!

    assert_nil setting.reload.black_friday_starts_at
    assert_not setting.black_friday?
  end

  test "black friday must end after it starts" do
    setting = store_settings(:default)
    starts = Time.zone.parse("2026-11-27 00:00")
    setting.assign_attributes(black_friday_starts_at: starts, black_friday_ends_at: starts)

    assert_not setting.valid?
    assert_includes setting.errors[:black_friday_ends_at], "precisa ser depois do início"

    setting.black_friday_ends_at = starts + 1.minute
    assert setting.valid?
  end
end
