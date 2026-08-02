require "test_helper"

class ProductShowTest < ActionDispatch::IntegrationTest
  test "a product that is still a draft is not reachable" do
    get product_path(slug: products(:staged).slug)

    assert_response :not_found
  end

  test "a product page advertises itself to link crawlers as a product" do
    product = products(:yellow)

    get product_path(slug: product.slug)

    assert_response :success
    assert_select "meta[property='og:type'][content='product']"
    assert_select "meta[property='og:title'][content=?]", product.title
    assert_select "meta[property='og:url'][content$=?]", product_path(slug: product.slug)
    assert_select "meta[property='product:price:currency'][content=?]", product.currency
    assert_select "meta[property='product:price:amount'][content=?]",
                  format("%.2f", product.price_cents / 100.0)
    assert_select "meta[name='twitter:card'][content='summary_large_image']"

    image = css_select("meta[property='og:image']").first["content"]
    assert image.start_with?("http"), "og:image must be absolute, got #{image.inspect}"
  end

  test "a product with no price omits the price tags rather than advertising zero" do
    product = products(:staged)
    product.update!(published: true, price_cents: 0)

    get product_path(slug: product.slug)

    assert_response :success
    assert_select "meta[property='og:type'][content='product']"
    assert_select "meta[property='product:price:amount']", count: 0
  end

  test "the current Jogo do Mês product shows the treatment and its brindes" do
    get product_path(slug: products(:yellow).slug)

    assert_response :success
    assert_match(/Jogo do Mês/, response.body)
    assert_select "section.mes-panel"
    assert_select "section.freebies"
    assert_match(/Poster Pokémon exclusivo/, response.body)
    assert_select ".free-card", count: 2
    assert_select ".free-card__kind", text: "Pôster"
    assert_select ".free-card__desc", text: "Arte exclusiva da edição, impressa em A3."
    assert_select "div.free-card__media", count: 2
    assert_select "a.free-card__media", false
  end

  test "a brinde with an attached image renders a Fancybox zoom link" do
    brinde = brindes(:current_brinde_poster)
    brinde.image.attach(
      io: File.open(file_fixture("sample_product.jpg")),
      filename: "brinde.jpg",
      content_type: "image/jpeg"
    )

    get product_path(slug: products(:yellow).slug)

    assert_response :success
    assert_select "a.free-card__media[data-fancybox]"
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
