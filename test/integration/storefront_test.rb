require "test_helper"

class StorefrontTest < ActionDispatch::IntegrationTest
  test "home page renders the category grids" do
    get root_path
    assert_response :success
    assert_select ".section-title__wordmark", /Extras & Acessórios/
    assert_select ".product-card__thumb--ph"
    assert_select ".cta-band"
  end

  test "home page renders active hero banners, first eager and the rest lazy" do
    2.times do |i|
      banner = HeroBanner.new(alt: "Destaque #{i}", position: i, active: true)
      banner.image.attach(
        io: File.open(file_fixture("sample_product.jpg")),
        filename: "hero.jpg",
        content_type: "image/jpeg"
      )
      banner.save!
    end
    HeroBanner.create!(active: false, position: 9) do |hidden|
      hidden.image.attach(
        io: File.open(file_fixture("sample_product.jpg")),
        filename: "hidden.jpg",
        content_type: "image/jpeg"
      )
    end

    get root_path
    assert_response :success
    assert_select "section.banner .banner__slot img", count: 2
    assert_select "section.banner .banner__slot img[loading=eager]", count: 1
    assert_select "section.banner .banner__slot img[loading=lazy]", count: 1
  end

  test "home page still renders when no GameOfTheMonth is set for the current month" do
    GameOfTheMonth.destroy_all
    get root_path
    assert_response :success
  end

  test "catalog index lists products and filters by term" do
    get products_path
    assert_response :success
    assert_select ".product-card"

    get products_path(term: "pokemon")
    assert_response :success
    assert_match(/Pokemon/i, response.body)
  end

  test "product page renders with a clean slug and no legacy Meloja markers" do
    get product_path(slug: products(:yellow).slug)
    assert_response :success
    assert_match products(:yellow).name, response.body
    assert_no_match(%r{meloja|//[^"'\s]*prismagames\.com\.br}i, response.body)
  end

  test "footer shows the Prisma Games contact email" do
    get root_path
    assert_response :success
    assert_match("contato@prismagames.com.br", response.body)
  end

  test "unknown product slug returns 404" do
    get product_path(slug: "does-not-exist")
    assert_response :not_found
  end

  test "category page renders; unknown category is 404" do
    get category_path(slug: "game-boy-color")
    assert_response :success
    assert_select ".product-card"

    get category_path(slug: "no-such-console")
    assert_response :not_found
  end

  test "drawer renders the published product count" do
    get root_path
    assert_response :success
    assert_match(/Todos os jogos/, response.body)
  end

test "every static page route renders" do
    [
      perguntas_frequentes_path,
      direitos_path
    ].each do |path|
      get path
      assert_response :success, "expected #{path} to render"
    end
  end

  test "unknown static page slug 404s — no matching route" do
    get "/pagina/desconhecido"
    assert_response :not_found
  end

  test "cookie banner renders until the acceptCookies cookie is present" do
    get root_path
    assert_select ".cookiealert"

    cookies[:acceptCookies] = "true"
    get root_path
    assert_select ".cookiealert", false, "accepted users should not get the banner at all"
  end
end
