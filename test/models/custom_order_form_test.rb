require "test_helper"

class CustomOrderFormTest < ActiveSupport::TestCase
  test "text returns the stored string when one is set" do
    assert_equal "Monte seu cartucho", custom_order_forms(:pedido_game_form).text(:title)
  end

  test "text falls back to the default when the column is blank" do
    form = custom_order_forms(:pedido_game_form)
    assert_equal CustomOrderForm::DEFAULTS[:subtitle], form.text(:subtitle)

    form.title = "   "
    assert_equal CustomOrderForm::DEFAULTS[:title], form.text(:title)
  end

  test "a brand new form answers every key with its default" do
    form = CustomOrderForm.new
    CustomOrderForm::DEFAULTS.each { |key, default| assert_equal default, form.text(key) }
  end

  test "every editable string is length capped" do
    form = custom_order_forms(:pedido_game_form)
    CustomOrderForm::LIMITS.each do |field, limit|
      form.assign_attributes(field => "a" * (limit + 1))
      assert_not form.valid?, "expected #{field} to reject #{limit + 1} characters"
      form.assign_attributes(field => "a" * limit)
      assert form.valid?, "expected #{field} to accept #{limit} characters"
    end
  end
end
