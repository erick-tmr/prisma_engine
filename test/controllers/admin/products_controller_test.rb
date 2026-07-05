require "test_helper"

module Admin
  class ProductsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    def graph(**overrides)
      {
        options: [ { group_name: "Idioma", values: [ { name: "Português BR", weight: 0 } ] } ],
        tags: [],
        photos: [],
        gotm: { enabled: false }
      }.merge(overrides).to_json
    end

    def base_params(**overrides)
      {
        name: "Zelda DX", category_id: categories(:gb_color).id, price: "199,90",
        description: "<p>oi</p>", weight_grams: 60, currency: "BRL", published: "1", graph: graph
      }.merge(overrides)
    end

    test "every action redirects non-admins to the backoffice login" do
      product = products(:yellow)
      get admin_products_path
      assert_redirected_to admin_login_path
      get new_admin_product_path
      assert_redirected_to admin_login_path
      post admin_products_path, params: { product: base_params }
      assert_redirected_to admin_login_path
      get edit_admin_product_path(product)
      assert_redirected_to admin_login_path
      patch admin_product_path(product), params: { product: base_params }
      assert_redirected_to admin_login_path
    end

    test "index lists the catalog for an admin" do
      sign_in users(:admin)
      get admin_products_path

      assert_response :success
      assert_match products(:yellow).name, response.body
      assert_select "[data-catalog]"
      assert_select "tr[data-row]"
    end

    test "new renders the editor with defaults" do
      sign_in users(:admin)
      get new_admin_product_path

      assert_response :success
      assert_select "form[data-catalog-editor]"
      assert_select "#f-weight[value=?]", "60"
    end

    test "edit renders the editor hydrated from the product" do
      sign_in users(:admin)
      product = products(:yellow)
      get edit_admin_product_path(product)

      assert_response :success
      assert_select "form[data-catalog-editor]"
      assert_select "#f-name[value=?]", product.name
    end

    test "create persists a product and its graph, then redirects with a notice" do
      sign_in users(:admin)

      assert_difference -> { Product.count }, 1 do
        post admin_products_path, params: { product: base_params(graph: graph(tags: [ "pokemon", "rpg" ])) }
      end

      product = Product.find_by(name: "Zelda DX")
      assert_redirected_to admin_products_path
      assert_equal "zelda-dx", product.slug
      assert_equal 19_990, product.price_cents
      assert_equal %w[pokemon rpg].sort, product.tags.map(&:name).sort
      assert_equal 1, product.product_options.count
      follow_redirect!
      assert_select ".toast", text: /Zelda DX/
    end

    test "create re-renders unprocessable when the product is invalid" do
      sign_in users(:admin)

      assert_no_difference -> { Product.count } do
        post admin_products_path, params: { product: base_params(name: "") }
      end

      assert_response :unprocessable_entity
      assert_select "form[data-catalog-editor]"
    end

    test "update edits the core fields, options and tags" do
      sign_in users(:admin)
      product = products(:yellow)

      patch admin_product_path(product), params: { product: base_params(
        name: "Yellow Remaster", category_id: product.category_id, weight_grams: 30, price: "150,00",
        graph: graph(
          options: [ { group_name: "Versão", values: [ { name: "DX", weight: 12 } ] } ],
          tags: [ "zelda" ]
        )
      ) }

      assert_redirected_to admin_products_path
      product.reload
      assert_equal "Yellow Remaster", product.name
      assert_equal 30, product.weight_grams
      assert_equal 15_000, product.price_cents
      assert_equal [ "Versão" ], product.product_options.pluck(:group_name).uniq
      assert_equal 12, product.product_options.first.weight_delta_grams
      assert_equal [ "zelda" ], product.tags.map(&:name)
    end

    test "update attaches an uploaded photo with its alt text" do
      sign_in users(:admin)
      product = products(:yellow)
      file = fixture_file_upload("sample_product.jpg", "image/jpeg")

      patch admin_product_path(product), params: { product: base_params(
        name: product.name, category_id: product.category_id,
        graph: graph(photos: [ { key: "p-0", alt: "Capa nova" } ]),
        photo_files: { "p-0" => file }
      ) }

      assert_redirected_to admin_products_path
      photo = product.reload.product_photos.in_display_order.first
      assert photo.image.attached?
      assert_equal "Capa nova", photo.alt_text
    end

    test "update turns Jogo do Mês on, creating the edition, join and brinde" do
      sign_in users(:admin)
      product = products(:metroid)
      file = fixture_file_upload("sample_product.jpg", "image/jpeg")

      patch admin_product_path(product), params: { product: base_params(
        name: product.name, category_id: product.category_id, weight_grams: 22,
        graph: graph(gotm: {
          enabled: true, year: 2030, month: 5, position: 2, blurb: "Edição especial",
          brindes: [ { key: "b-0", caption: "Pôster", kind: "Colecionável", description: "Arte A3", weight: 5 } ]
        }),
        brinde_files: { "b-0" => file }
      ) }

      assert_redirected_to admin_products_path
      join = product.reload.game_of_the_month_products.first
      assert_equal 2030, join.game_of_the_month.year
      assert_equal 5, join.game_of_the_month.month
      assert_equal "Edição especial", join.blurb
      assert_equal 2, join.position
      brinde = join.brindes.first
      assert brinde.image.attached?
      assert_equal "Pôster", brinde.caption
      assert_equal 5, brinde.weight_grams
    end

    test "update turns Jogo do Mês off, removing the join and its brindes" do
      sign_in users(:admin)
      product = products(:yellow) # fixtures link it to the current edition

      assert product.game_of_the_month_products.exists?
      patch admin_product_path(product), params: { product: base_params(
        name: product.name, category_id: product.category_id, graph: graph(gotm: { enabled: false })
      ) }

      assert_redirected_to admin_products_path
      assert_empty product.reload.game_of_the_month_products
    end
  end
end
