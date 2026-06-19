require "application_system_test_case"

class StorefrontSmokeTest < ApplicationSystemTestCase
  test "the home page renders the header and cart" do
    visit root_path

    assert_selector "a.header__logo"
    assert_selector "[data-cart-count]"
    assert_title "Prisma Games"
  end

  test "the catalog lists published products" do
    visit products_path

    assert_selector ".product-card", minimum: 1
    assert_text products(:yellow).title
  end
end
