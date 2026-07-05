require "application_system_test_case"

class AdminCatalogTest < ApplicationSystemTestCase
  test "an operator filters the catalog by search" do
    login_as_user(users(:admin))
    visit admin_products_path

    assert_selector "tr[data-row]", minimum: 3
    fill_in "c-q", with: "metroid"

    within "#catalog-body" do
      assert_text products(:metroid).name
      assert_no_text products(:yellow).name
    end
  end

  test "an operator edits a product and saves it" do
    login_as_user(users(:admin))
    visit admin_products_path

    find("tr[data-row]", text: products(:game_box).name).click
    assert_selector "form[data-catalog-editor]"

    fill_in "f-name", with: "Caixa Premium"
    fill_in "f-price", with: "40,00"

    accept_prompt(with: "raro") { find(".tag-add").click }
    assert_selector ".tagchip", text: "raro"

    find("#ed-save").click

    assert_current_path admin_products_path
    assert_text "Caixa Premium"

    products(:game_box).reload.tap do |product|
      assert_equal "Caixa Premium", product.name
      assert_equal 4_000, product.price_cents
      assert_includes product.tags.map(&:name), "raro"
    end
  end

  test "an operator creates a product from scratch" do
    login_as_user(users(:admin))
    visit new_admin_product_path

    assert_selector "form[data-catalog-editor]"
    fill_in "f-name", with: "Wario Land 3"
    fill_in "f-price", with: "210,00"
    find("#ed-save").click

    assert_current_path admin_products_path
    product = Product.find_by(name: "Wario Land 3")
    assert_equal 21_000, product.price_cents
    assert_equal "wario-land-3", product.slug
    assert product.published?
  end
end
