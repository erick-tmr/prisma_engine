require "test_helper"

class VariantDisplayHelperTest < ActionView::TestCase
  test "variant_group_icon maps known groups and falls back" do
    assert_equal "bi-translate", variant_group_icon("Idioma")
    assert_equal "bi-box2", variant_group_icon("Caixa")
    assert_equal "bi-tag", variant_group_icon("Etiqueta")
    assert_equal "bi-sliders2", variant_group_icon("Desconhecido")
  end

  test "variant_option_flag returns a flag for known languages, nil otherwise" do
    assert_equal "🇧🇷", variant_option_flag("Português BR")
    assert_equal "🇺🇸", variant_option_flag("Inglês")
    assert_nil variant_option_flag("Com caixa")
  end

  test "variant_delta_label is nil for a zero delta" do
    assert_nil variant_delta_label(0)
  end

  test "variant_delta_label signs a positive delta" do
    assert_equal "+R$ 20.00", variant_delta_label(2000)
  end

  test "variant_delta_label signs a negative delta with a minus sign" do
    assert_equal "−R$ 15.00", variant_delta_label(-1500)
  end
end
