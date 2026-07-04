require "test_helper"

class VariantDisplayHelperTest < ActionView::TestCase
  test "variant_group_icon maps known groups and falls back" do
    assert_equal "bi-translate", variant_group_icon("Idioma")
    assert_equal "bi-box2", variant_group_icon("Caixa")
    assert_equal "bi-tag", variant_group_icon("Label")
    assert_equal "bi-sliders2", variant_group_icon("Desconhecido")
  end

  test "variant_option_flag returns a flag for known languages, nil otherwise" do
    assert_equal "🇧🇷", variant_option_flag("Português BR")
    assert_equal "🇺🇸", variant_option_flag("Inglês")
    assert_equal "🇯🇵", variant_option_flag("Japonês")
    assert_nil variant_option_flag("Com caixa")
  end

  test "variant_language_slug returns a colour slug for known languages, nil otherwise" do
    assert_equal "br", variant_language_slug("Português BR")
    assert_equal "en", variant_language_slug("Inglês")
    assert_equal "jp", variant_language_slug("Japonês")
    assert_nil variant_language_slug("Com caixa")
  end
end
