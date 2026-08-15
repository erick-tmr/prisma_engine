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

  test "format_brl converts cents to a R$ string with comma decimals and grouped thousands" do
    assert_equal "R$ 12,34", format_brl(1_234)
    assert_equal "R$ 1.000,00", format_brl(100_000)
    assert_equal "R$ 50.478,44", format_brl(5_047_844)
    assert_equal "R$ 0,00", format_brl(0)
  end

  test "order_payment_method_label maps the real capture methods" do
    assert_equal "Pix", order_payment_method_label("pix")
    assert_equal "Cartão de crédito", order_payment_method_label("credit_card")
  end

  test "order_payment_method_label shows a pending label when no method is set yet" do
    assert_equal "Aguardando pagamento", order_payment_method_label(nil)
    assert_equal "Aguardando pagamento", order_payment_method_label("")
  end

  test "order_payment_method_label falls back to a humanized label for the unexpected" do
    assert_equal "Debit card", order_payment_method_label("debit_card")
  end

  test "order_payment_method_icon maps the real capture methods" do
    assert_equal "bi-cash-coin", order_payment_method_icon("pix")
    assert_equal "bi-credit-card", order_payment_method_icon("credit_card")
  end

  test "order_payment_method_icon falls back to a generic wallet" do
    assert_equal "bi-wallet2", order_payment_method_icon(nil)
    assert_equal "bi-wallet2", order_payment_method_icon("debit_card")
  end

  test "order_payment_status_icon marks paid with a check and anything else with an hourglass" do
    assert_equal "bi-check-circle-fill", order_payment_status_icon(:paid)
    assert_equal "bi-hourglass-split", order_payment_status_icon(:pending)
    assert_equal "bi-hourglass-split", order_payment_status_icon("refunded")
  end

  test "format_cpf masks 11 digits as 000.000.000-00" do
    assert_equal "111.444.777-35", format_cpf("11144477735")
  end

  test "format_cpf returns the input as-is when it isn't 11 digits" do
    assert_equal "abc", format_cpf("abc")
    assert_equal "12345", format_cpf("12345")
    assert_equal "", format_cpf(nil)
  end

  test "account_avatar_initials uses first and last token initials" do
    assert_equal "ET", account_avatar_initials("Erick Takeshi")
    assert_equal "ER", account_avatar_initials("Erick Takeshi Mine Rezende")
    assert_equal "JS", account_avatar_initials("João da Silva")
  end

  test "account_avatar_initials handles a single-token name" do
    assert_equal "M", account_avatar_initials("Madonna")
  end

  test "account_avatar_initials returns empty string for blank input" do
    assert_equal "", account_avatar_initials(nil)
    assert_equal "", account_avatar_initials("")
    assert_equal "", account_avatar_initials("   ")
  end
  test "the return label is only ready once the saga finished writing it" do
    order = orders(:delivered)
    assert_not order_return_label_ready?(order)

    Shipping::AuthorizeReturn.call(order: order)
    assert_not order_return_label_ready?(order.reload)

    order.return_shipping_label.mark_ready!(filename: "d.pdf", pdf: "x")
    assert order_return_label_ready?(order.reload)
  end

  test "an authorized return explains itself differently while its label is building" do
    order = orders(:delivered)
    Shipping::AuthorizeReturn.call(order: order)
    assert_equal I18n.t("account.orders.states.awaiting_return.description_pending"),
                 order_state_description(order.reload)

    order.return_shipping_label.mark_ready!(filename: "d.pdf", pdf: "x")
    assert_equal I18n.t("account.orders.states.awaiting_return.description"),
                 order_state_description(order.reload)
  end

  test "every other status reads its own description" do
    assert_equal I18n.t("account.orders.states.delivered.description"),
                 order_state_description(orders(:delivered))
  end
end
