require "test_helper"

class AccountHelperTest < ActionView::TestCase
  test "number_to_cep formats 8 digits as 5-3" do
    assert_equal "12345-678", number_to_cep("12345678")
  end

  test "number_to_cep returns the input as-is when it isn't 8 digits" do
    assert_equal "abc", number_to_cep("abc")
    assert_equal "1234567", number_to_cep("1234567")
    assert_equal "", number_to_cep(nil)
  end

  test "format_brl converts cents to a R$ string with comma decimals" do
    assert_equal "R$ 12,34", format_brl(1_234)
    assert_equal "R$ 1000,00", format_brl(100_000)
    assert_equal "R$ 0,00", format_brl(0)
  end

  test "order_status_badge_class maps known states to Bootstrap classes" do
    assert_equal "text-bg-success", order_status_badge_class("entregue")
    assert_equal "text-bg-success", order_status_badge_class("enviado")
    assert_equal "text-bg-primary", order_status_badge_class("em_producao")
    assert_equal "text-bg-warning", order_status_badge_class("aguardando_pagamento")
    assert_equal "text-bg-danger", order_status_badge_class("problema_na_producao")
  end

  test "order_status_badge_class falls back to secondary for unknown states" do
    assert_equal "text-bg-secondary", order_status_badge_class("unknown")
  end

  test "order_payment_method_label maps the known PSPs" do
    assert_equal "Pix", order_payment_method_label(:pix)
    assert_equal "InfinitePay (cartão)", order_payment_method_label(:infinite_pay_card)
  end

  test "order_payment_method_label falls back to a humanized label" do
    assert_equal "Other psp", order_payment_method_label(:other_psp)
  end
end
