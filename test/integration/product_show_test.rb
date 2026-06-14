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
    # metroid is the past month's pick, not the current one.
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

  test "variant pills carry their price delta for the live price script" do
    get product_path(slug: products(:yellow).slug)

    assert_response :success
    # yellow's "Com caixa" option is +R$10 in the fixtures.
    assert_select "button.variant-pill[data-delta='1000']"
    assert_match(/\+R\$ 10\.00/, response.body)
  end
end
