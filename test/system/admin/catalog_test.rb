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

  test "an operator pages through a catalog larger than one page" do
    40.times do |i|
      Product.create!(category: categories(:gb_color), name: "Filler Game #{i}",
                      price_cents: 1_000, weight_grams: 20, published: true)
    end
    total = Product.count

    login_as_user(users(:admin))
    visit admin_products_path

    assert_selector "#catalog-count", text: "#{total} produtos"
    assert_selector ".tbl-foot .foot-range", text: "Mostrando 1–30 de #{total} produtos"
    assert_selector "tr[data-row]", count: 30

    find(".tbl-foot a.pg", text: "2", exact_text: true).click
    assert_selector ".tbl-foot a.pg.on", text: "2"
    assert_current_path(/page=2/)
    assert_selector "tr[data-row]", count: total - 30

    # Narrowing the filter from page 2 must land the operator back on page 1.
    fill_in "c-q", with: "Filler"
    assert_selector "#catalog-count", text: "40 produtos"
    assert_selector "tr[data-row]", count: 30
    assert_current_path(/q=Filler/)
    assert_no_current_path(/page=2/)
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

  test "an operator turns a product into a made-to-order one and words its form" do
    login_as_user(users(:admin))
    visit edit_admin_product_path(products(:game_box))

    assert_no_selector "#co-body", visible: true
    find(".custom-order-panel .switch .track").click
    assert_selector "#co-body", visible: true

    fill_in "f-co-title", with: "Monte a sua caixa"
    assert_selector "#cop-title", text: "Monte a sua caixa"

    find("#ed-save").click
    assert_current_path admin_products_path

    products(:game_box).reload.tap do |product|
      assert product.custom_order?
      assert_equal "Monte a sua caixa", product.custom_order_form.title
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
