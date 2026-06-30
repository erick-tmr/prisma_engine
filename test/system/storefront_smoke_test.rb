require "application_system_test_case"

class StorefrontSmokeTest < ApplicationSystemTestCase
  test "the home page renders the header and cart" do
    visit root_path

    assert_selector "a.header__logo"
    assert_selector "[data-cart-count]"
    assert_title "Prisma Games"
  end

  test "the home page renders the Extras & Acessórios section and CTA band" do
    visit root_path

    assert_selector ".section-title__wordmark", text: /extras & acessórios/i
    assert_selector ".product-card__thumb--ph", minimum: 1
    assert_selector ".cta-band__btn"
  end

  test "the catalog lists published products with loaded images" do
    visit products_path

    assert_selector ".product-card", minimum: 1
    assert_text products(:yellow).title

    image = find(".product-card__thumb img", match: :first)
    assert image.evaluate_script("this.complete && this.naturalWidth > 0"),
           "expected the product image to load, not 404/broken"
  end
end
