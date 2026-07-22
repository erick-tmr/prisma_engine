gotm_assets_dir = Rails.root.join("db/seeds/gotm")

def attach_gotm_image!(attachable, path)
  attachable.image.attach(
    io:           File.open(path),
    filename:     File.basename(path),
    content_type: "image/jpeg"
  )
end

editions = [
  {
    slug: "mario-golf", name: "Mario Golf",
    game_image: gotm_assets_dir.join("mario-golf-game2-cropped.jpeg"),
    brindes: [
      { caption: "Pôster", kind: "Pôster",
        description: "Arte exclusiva de Mario Golf, impressa em papel couché.",
        image: gotm_assets_dir.join("mario-golf-poster.jpeg"), weight_grams: 5 },
      { caption: "Cartão postal", kind: "Colecionável",
        description: "Cartão postal ilustrado do campo de golfe de Mario Golf.",
        image: gotm_assets_dir.join("mario-golf-postal-card.jpeg"), weight_grams: 5 },
      { caption: "Cartão de trivia", kind: "Curiosidades",
        description: "Cartão com curiosidades e recordes do jogo.",
        image: gotm_assets_dir.join("mario-golf-trivia.jpeg"), weight_grams: 2 }
    ]
  },
  {
    slug: "mario-tennis", name: "Mario Tennis",
    game_image: gotm_assets_dir.join("mario-tennis-game-cropped.jpeg"),
    brindes: [
      { caption: "Pôster", kind: "Pôster",
        description: "Arte exclusiva de Mario Tennis, impressa em papel couché.",
        image: gotm_assets_dir.join("mario-tennis-poster.jpeg"), weight_grams: 5 },
      { caption: "Cartão postal", kind: "Colecionável",
        description: "Cartão postal ilustrado da Royal Tennis Academy.",
        image: gotm_assets_dir.join("mario-tennis-postal-card.jpeg"), weight_grams: 5 },
      { caption: "Cartão de trivia", kind: "Curiosidades",
        description: "Cartão com curiosidades e recordes do jogo.",
        image: gotm_assets_dir.join("mario-golf-trivia.jpeg"), weight_grams: 2 }
    ]
  }
]

required_files = editions.flat_map { |e| [ e[:game_image] ] + e[:brindes].map { |b| b[:image] } }

if required_files.all? { |path| File.exist?(path) }
  category = Category.find_by(slug: "game-boy-color")

  gotm = GameOfTheMonth.find_or_initialize_by(year: Date.current.year, month: Date.current.month)
  gotm.note = "Mario Golf & Mario Tennis" if gotm.note != "Mario Golf & Mario Tennis"
  gotm.save!

  kept_products = editions.map do |edition|
    product = Product.find_or_initialize_by(slug: edition[:slug])
    product.name         = edition[:name]
    product.category     = category
    product.price_cents  = 20_000
    product.weight_grams ||= 22
    product.published    = true
    product.save!

    if product.product_photos.none?
      photo = product.product_photos.build(position: 0)
      attach_gotm_image!(photo, edition[:game_image])
      photo.save!
    end

    product
  end
  gotm.game_of_the_month_products.where.not(product: kept_products).destroy_all

  editions.each_with_index do |edition, index|
    product = kept_products[index]
    gp = GameOfTheMonthProduct.find_or_create_by!(game_of_the_month: gotm, product: product) do |new_gp|
      new_gp.position = index
    end
    gp.update!(position: index) if gp.position != index

    wanted_captions = edition[:brindes].map { |b| b[:caption] }
    next if gp.brindes.in_display_order.pluck(:caption) == wanted_captions

    gp.brindes.destroy_all
    edition[:brindes].each_with_index do |attrs, b_index|
      brinde = gp.brindes.build(
        caption:     attrs[:caption],
        kind:        attrs[:kind],
        description: attrs[:description],
        weight_grams: attrs[:weight_grams],
        position:    b_index
      )
      attach_gotm_image!(brinde, attrs[:image])
      brinde.save!
    end
  end

  puts "Jogo do Mês: #{gotm.note} (#{gotm.year}-#{gotm.month}), " \
       "#{gotm.products.count} produto(s), #{gotm.brindes.count} brinde(s)"
end
