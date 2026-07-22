require "test_helper"

class CategoriesShowTest < ActionDispatch::IntegrationTest
  test "lists the current Jogo do Mês picks before the rest of the console catalog" do
    filler = Product.create!(
      name: "Zzz Filler Game", category: categories(:gb_color),
      price_cents: 17_500, weight_grams: 22, published: true
    )

    get category_path(slug: "game-boy-color")

    assert_response :success
    assert_operator response.body.index(products(:yellow).name), :<,
                    response.body.index(filler.name),
                    "expected the Jogo do Mês pick to render before an ordinary product"
  end

  test "renders the console catalog when there is no current Jogo do Mês" do
    GameOfTheMonth.destroy_all

    get category_path(slug: "game-boy-color")

    assert_response :success
    assert_select ".product-card"
  end

  test "is reachable by slug alone: no category_id query needed" do
    get category_path(slug: "game-boy-color")
    assert_response :success
    assert_equal "/produtos/game-boy-color", category_path(slug: "game-boy-color")
  end
end
