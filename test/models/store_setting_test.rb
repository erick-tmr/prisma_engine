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
end
