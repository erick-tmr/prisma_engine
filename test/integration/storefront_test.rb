require "test_helper"

class StorefrontTest < ActionDispatch::IntegrationTest
  test "home page renders the category grids" do
    get root_path
    assert_response :success
    assert_select ".section-title__wordmark", /Extras & Acessórios/
    assert_select ".product-card__thumb--ph"
    assert_select ".cta-band"
  end

  test "home page lists the current Jogo do Mês pick before the rest of its category grid" do
    filler = Product.create!(
      name: "Zzz Filler Game", category: categories(:gb_color),
      price_cents: 17_500, weight_grams: 22, published: true
    )

    get root_path

    assert_response :success
    assert_operator response.body.index(products(:yellow).name), :<,
                    response.body.index(filler.name),
                    "expected the Jogo do Mês pick to render before an ordinary product"
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

  test "home page hides the Jogo do Mês band when no GameOfTheMonth is set for the current month" do
    GameOfTheMonth.destroy_all
    get root_path
    assert_response :success
    assert_select ".gotm-band", false
  end

  test "home page hides the Jogo do Mês band when the current edition has no products yet" do
    game_of_the_months(:current_month).game_of_the_month_products.destroy_all
    get root_path
    assert_response :success
    assert_select ".gotm-band", false
  end

  test "home page renders the current Jogo do Mês carousel with every edition's product" do
    get root_path
    assert_response :success
    assert_select ".gotm-band"
    assert_select ".gotm-slide", count: 2
    assert_select ".gotm-slide__title", text: products(:yellow).name
    assert_select ".gotm-slide__title", text: products(:placeholder).name
    assert_select ".gotm-slide__blurb", count: 2
    # Only yellow's slide has brindes (per-product kit); placeholder has none.
    assert_select ".gotm-brindes__thumbs .gotm-brinde", count: 2
  end

  test "catalog index lists products and filters by term" do
    get products_path
    assert_response :success
    assert_select ".product-card"

    get products_path(term: "pokemon")
    assert_response :success
    assert_match(/Pokemon/i, response.body)
  end

  test "catalog index escapes LIKE wildcards so a bare % is not a match-all" do
    Product.create!(
      name: "Wildcard Sentinel", category: categories(:gb_color),
      price_cents: 10_000, weight_grams: 20, published: true
    )

    get products_path(term: "%")
    assert_response :success
    assert_no_match(/Wildcard Sentinel/, response.body)
  end

  test "catalog index floats the current Jogo do Mês pick above ordinary products" do
    ordinary = Product.create!(
      name: "Aaa Ordinary Game", category: categories(:gb_color),
      price_cents: 10_000, weight_grams: 20, published: true
    )
    featured = Product.create!(
      name: "Zzz Featured Game", category: categories(:gb_color),
      price_cents: 10_000, weight_grams: 20, published: true
    )
    game_of_the_months(:current_month).game_of_the_month_products.create!(product: featured, position: 0)

    get products_path

    assert_response :success
    assert_operator response.body.index(featured.name), :<, response.body.index(ordinary.name),
                    "expected the Jogo do Mês pick to render before an ordinary, lower-id product"
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

  test "footer credits the developer with a link to their site" do
    get root_path
    assert_response :success
    assert_select "footer.footer a[href='https://ericktakeshi.com.br/']", text: /Erick Takeshi/
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

  test "home page issues a bounded number of SQL queries (guards against the card N+1)" do
    count = count_sql_queries { get root_path }
    assert_operator count, :<=, 30,
      "home page ran #{count} SQL queries; expected a bounded set. The product cards and " \
      "Jogo do Mês band must render from eager-loaded associations, not per-card queries."
  end

  private

  def count_sql_queries
    queries = 0
    counter = lambda do |*, payload|
      next if payload[:name] == "SCHEMA" || payload[:cached]
      next if /\A\s*(BEGIN|COMMIT|RELEASE|SAVEPOINT|ROLLBACK)/i.match?(payload[:sql])

      queries += 1
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    queries
  end
end
