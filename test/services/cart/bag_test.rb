require "test_helper"

class Cart::BagTest < ActiveSupport::TestCase
  def yellow
    products(:yellow)
  end

  def yellow_options
    [ product_options(:yellow_idioma_pt), product_options(:yellow_caixa_sem) ]
  end

  def pedido
    products(:pedido_game)
  end

  test "from_cookie tolerates nil + non-hash + unknown version" do
    assert_equal [], Cart::Bag.from_cookie(nil).items
    assert_equal [], Cart::Bag.from_cookie("rubbish").items
    assert_equal [], Cart::Bag.from_cookie({ "v" => 99, "items" => [ {} ] }).items
  end

  test "from_cookie drops rows that aren't hashes" do
    bag = Cart::Bag.from_cookie({ "v" => 1, "items" => [ "not a hash", 7, nil ] })
    assert_equal [], bag.items
  end

  test "update_options is a no-op for an unknown line id" do
    bag = Cart::Bag.new
    bag.add(product: yellow, quantity: 1, option_ids: [ product_options(:yellow_idioma_pt).id ])
    bag.update_options("missing", [ product_options(:yellow_idioma_en).id ])
    assert_equal [ product_options(:yellow_idioma_pt).id ], bag.items.first["o"]
  end

  test "from_cookie drops malformed rows (missing id / non-positive quantity)" do
    bag = Cart::Bag.from_cookie({
      "v" => 1,
      "items" => [
        { "id" => "abc12345", "p" => 1, "q" => 1, "o" => [ 1, 2 ] },
        { "id" => "",         "p" => 1, "q" => 1, "o" => [] },
        { "id" => "ok______", "p" => 0, "q" => 1, "o" => [] },
        { "id" => "ok______", "p" => 1, "q" => 0, "o" => [] }
      ]
    })
    assert_equal 1, bag.items.length
    assert_equal "abc12345", bag.items.first["id"]
  end

  test "add appends a new line with sorted option ids" do
    bag = Cart::Bag.new
    bag.add(product: yellow, quantity: 2, option_ids: yellow_options.map(&:id).reverse)
    assert_equal 1, bag.items.length
    line = bag.items.first
    assert_equal yellow.id, line["p"]
    assert_equal 2,         line["q"]
    assert_equal yellow_options.map(&:id).sort, line["o"]
    assert_equal 8,         line["id"].length
  end

  test "add merges an identical (product, options) into a single line" do
    bag = Cart::Bag.new
    bag.add(product: yellow, quantity: 1, option_ids: yellow_options.map(&:id))
    bag.add(product: yellow, quantity: 2, option_ids: yellow_options.map(&:id))
    assert_equal 1, bag.items.length
    assert_equal 3, bag.items.first["q"]
  end

  test "add with different options creates distinct lines" do
    bag = Cart::Bag.new
    bag.add(product: yellow, quantity: 1, option_ids: [ product_options(:yellow_idioma_pt).id ])
    bag.add(product: yellow, quantity: 1, option_ids: [ product_options(:yellow_idioma_en).id ])
    assert_equal 2, bag.items.length
  end

  test "add stores the made-to-order request and strips the game" do
    bag = Cart::Bag.new
    bag.add(product: pedido, quantity: 1, option_ids: [], request: { game: "  Pokemon Unbound  ", notes: "   " })
    assert_equal({ "g" => "Pokemon Unbound" }, bag.items.first["r"])
  end

  test "add keeps request notes when present" do
    bag = Cart::Bag.new
    bag.add(product: pedido, quantity: 1, option_ids: [], request: { game: "Zelda", notes: "carcaça azul" })
    assert_equal({ "g" => "Zelda", "n" => "carcaça azul" }, bag.items.first["r"])
  end

  test "add omits the request when the game is blank" do
    bag = Cart::Bag.new
    bag.add(product: pedido, quantity: 1, option_ids: [], request: { game: "  ", notes: "orphan note" })
    refute bag.items.first.key?("r")
  end

  test "add merges lines carrying an identical request" do
    bag = Cart::Bag.new
    bag.add(product: pedido, quantity: 1, option_ids: [], request: { game: "Zelda", notes: "azul" })
    bag.add(product: pedido, quantity: 2, option_ids: [], request: { game: "Zelda", notes: "azul" })
    assert_equal 1, bag.items.length
    assert_equal 3, bag.items.first["q"]
  end

  test "add keeps requests with different games on separate lines" do
    bag = Cart::Bag.new
    bag.add(product: pedido, quantity: 1, option_ids: [], request: { game: "Zelda" })
    bag.add(product: pedido, quantity: 1, option_ids: [], request: { game: "Metroid" })
    assert_equal 2, bag.items.length
  end

  test "add caps the request game and notes lengths" do
    bag = Cart::Bag.new
    bag.add(product: pedido, quantity: 1, option_ids: [], request: { game: "g" * 200, notes: "n" * 800 })
    request = bag.items.first["r"]
    assert_equal 120, request["g"].length
    assert_equal 280, request["n"].length
  end

  test "from_cookie hydrates a request and normalises a blank one away" do
    bag = Cart::Bag.from_cookie({
      "v" => 1,
      "items" => [
        { "id" => "withreq_", "p" => pedido.id, "q" => 1, "o" => [], "r" => { "g" => "Zelda", "n" => "azul" } },
        { "id" => "blankg__", "p" => pedido.id, "q" => 1, "o" => [], "r" => { "g" => "  " } }
      ]
    })
    assert_equal({ "g" => "Zelda", "n" => "azul" }, bag.items.find { |i| i["id"] == "withreq_" }["r"])
    refute bag.items.find { |i| i["id"] == "blankg__" }.key?("r")
  end

  test "lines exposes the requested game and notes" do
    bag = Cart::Bag.new
    bag.add(product: pedido, quantity: 1, option_ids: [], request: { game: "Zelda", notes: "azul" })
    line = bag.lines.first
    assert_equal "Zelda", line.requested_game
    assert_equal "azul", line.request_notes
  end

  test "to_cookie round-trips a request line" do
    bag = Cart::Bag.new
    bag.add(product: pedido, quantity: 1, option_ids: [], request: { game: "Zelda", notes: "azul" })
    round_tripped = Cart::Bag.from_cookie(JSON.parse(bag.to_cookie.to_json))
    assert_equal bag.items, round_tripped.items
  end

  test "add clamps quantity to the 1..99 range" do
    bag = Cart::Bag.new
    bag.add(product: yellow, quantity: 0, option_ids: [])
    assert_equal 1, bag.items.first["q"]

    bag2 = Cart::Bag.new
    bag2.add(product: yellow, quantity: 500, option_ids: [])
    assert_equal 99, bag2.items.first["q"]
  end

  test "update_quantity clamps + ignores unknown ids" do
    bag = Cart::Bag.new
    bag.add(product: yellow, quantity: 1, option_ids: [])
    line_id = bag.items.first["id"]

    bag.update_quantity(line_id, 5)
    assert_equal 5, bag.items.first["q"]

    bag.update_quantity(line_id, 999)
    assert_equal 99, bag.items.first["q"]

    bag.update_quantity("missing!", 7) # silently ignored
    assert_equal 99, bag.items.first["q"]
  end

  test "update_options swaps the chosen options on a line" do
    bag = Cart::Bag.new
    bag.add(product: yellow, quantity: 1, option_ids: [ product_options(:yellow_idioma_pt).id ])
    line_id = bag.items.first["id"]

    bag.update_options(line_id, [ product_options(:yellow_idioma_en).id ])
    assert_equal [ product_options(:yellow_idioma_en).id ], bag.items.first["o"]
    # line id survived the edit
    assert_equal line_id, bag.items.first["id"]
  end

  test "remove drops the line by id and is a no-op for unknown ids" do
    bag = Cart::Bag.new
    bag.add(product: yellow, quantity: 1, option_ids: [])
    line_id = bag.items.first["id"]

    bag.remove("nope")
    assert_equal 1, bag.items.length

    bag.remove(line_id)
    assert_equal 0, bag.items.length
  end

  test "lines drops items whose product is unpublished or missing" do
    bag = Cart::Bag.from_cookie({
      "v" => 1,
      "items" => [
        { "id" => "live____", "p" => yellow.id,                "q" => 1, "o" => [] },
        { "id" => "unpub___", "p" => products(:hidden).id,     "q" => 1, "o" => [] },
        { "id" => "gone____", "p" => 9_999_999,                "q" => 1, "o" => [] }
      ]
    })
    line_ids = bag.lines.map(&:id)
    assert_equal [ "live____" ], line_ids
  end

  test "lines drops items whose option_ids no longer belong to the product" do
    foreign_opt = ProductOption.create!(
      product: products(:metroid), group_name: "Idioma", name: "Espanhol", position: 0
    )
    bag = Cart::Bag.from_cookie({
      "v" => 1,
      "items" => [
        { "id" => "good____", "p" => yellow.id, "q" => 1, "o" => [ product_options(:yellow_idioma_pt).id ] },
        { "id" => "bad_____", "p" => yellow.id, "q" => 1, "o" => [ foreign_opt.id ] }
      ]
    })
    line_ids = bag.lines.map(&:id)
    assert_equal [ "good____" ], line_ids
  end

  test "cleanup! rewrites items, returning true when anything was removed" do
    bag = Cart::Bag.from_cookie({
      "v" => 1,
      "items" => [
        { "id" => "live____", "p" => yellow.id, "q" => 1, "o" => [] },
        { "id" => "gone____", "p" => 9_999_999, "q" => 1, "o" => [] }
      ]
    })
    assert bag.cleanup!
    assert_equal 1, bag.items.length

    refute bag.cleanup!
  end

  test "subtotal_cents sums the product price times quantity" do
    bag = Cart::Bag.new
    bag.add(product: yellow, quantity: 2, option_ids: [ product_options(:yellow_caixa_com).id ])
    # 18000 base * 2 qty; options no longer move the price
    assert_equal 36_000, bag.subtotal_cents
    assert_equal "R$ 360,00", bag.subtotal_formatted
  end

  test "to_cookie round-trips through from_cookie" do
    bag = Cart::Bag.new
    bag.add(product: yellow, quantity: 3, option_ids: [ product_options(:yellow_idioma_pt).id ])
    round_tripped = Cart::Bag.from_cookie(JSON.parse(bag.to_cookie.to_json))
    assert_equal bag.items, round_tripped.items
  end

  test "total_quantity sums every line's qty" do
    bag = Cart::Bag.new
    bag.add(product: yellow,            quantity: 2, option_ids: [])
    bag.add(product: products(:metroid), quantity: 5, option_ids: [])
    assert_equal 7, bag.total_quantity
  end

  test "empty? reflects whether any items remain" do
    assert Cart::Bag.new.empty?

    bag = Cart::Bag.new
    bag.add(product: yellow, quantity: 1, option_ids: [])
    refute bag.empty?
  end

  test "total_weight_grams multiplies line weight by quantity, ignoring brindes when no line is GOTM" do
    bag = Cart::Bag.new
    bag.add(product: yellow, quantity: 3, option_ids: [ product_options(:yellow_caixa_com).id ])
    # (22 + 38) * 3 = 180
    assert_equal 180, bag.total_weight_grams(gotm_brindes_weight_by_product_id: {})
  end

  test "total_weight_grams adds brindes weight only for GOTM lines, scaled by quantity" do
    bag = Cart::Bag.new
    bag.add(product: yellow, quantity: 2, option_ids: [ product_options(:yellow_caixa_com).id ])
    bag.add(product: products(:metroid), quantity: 1, option_ids: [])
    # GOTM (yellow): (60 + 15) * 2 = 150
    # Non-GOTM (metroid): 22 * 1 = 22
    total = bag.total_weight_grams(gotm_brindes_weight_by_product_id: { yellow.id => 15 })
    assert_equal 172, total
  end

  test "total_weight_grams uses each GOTM product's own brindes weight" do
    bag = Cart::Bag.new
    bag.add(product: yellow, quantity: 1, option_ids: [])                 # GOTM, 15g kit
    bag.add(product: products(:placeholder), quantity: 2, option_ids: []) # GOTM, 8g kit
    # yellow: (22 + 15) * 1 = 37
    # placeholder: (22 + 8) * 2 = 60
    total = bag.total_weight_grams(
      gotm_brindes_weight_by_product_id: { yellow.id => 15, products(:placeholder).id => 8 }
    )
    assert_equal 97, total
  end
end
