require "test_helper"

class ProductShowTest < ActionDispatch::IntegrationTest
  test "the current Jogo do Mês product shows the treatment and its brindes" do
    get product_path(slug: products(:yellow).slug)

    assert_response :success
    assert_match(/Jogo do Mês/, response.body)
    assert_select "section.mes-panel"
    assert_select "section.freebies"
    assert_match(/Poster Pokémon exclusivo/, response.body)
  end

  test "an ordinary product shows no Jogo do Mês treatment" do
    get product_path(slug: products(:metroid).slug)

    assert_response :success
    assert_select "section.mes-panel", false
    assert_select "section.freebies", false
    assert_no_match(/Jogo do Mês/, response.body)
  end

  test "the product page still renders when no Jogo do Mês is set" do
    GameOfTheMonth.destroy_all

    get product_path(slug: products(:yellow).slug)

    assert_response :success
    assert_select "section.freebies", false
  end

  test "variant pills render without any price delta" do
    get product_path(slug: products(:yellow).slug)

    assert_response :success
    assert_select "button.variant-pill"
    assert_select "button.variant-pill[data-delta]", false
    assert_no_match(/\+R\$/, response.body)
  end
end
