game = Product.find_by(slug: "shantae")

if game
  gotm = GameOfTheMonth.find_or_initialize_by(year: Date.current.year, month: Date.current.month)
  gotm.note = "Shantae" if gotm.new_record?
  gotm.save!

  gp = GameOfTheMonthProduct.find_or_create_by!(game_of_the_month: gotm, product: game) do |new_gp|
    new_gp.position = 0
  end
  gp.update!(blurb: "A pirata mais adorada do Game Boy Color parte numa aventura cheia de transformações e humor.") if gp.blurb.blank?

  placeholder_image = Rails.root.join("public/images/stores/uploads/2475313/conversions/large.jpg")

  brinde_kit = [
    { caption: "Pôster A5",         weight_grams: 5 },
    { caption: "Cards x3",          weight_grams: 3 },
    { caption: "Cartão postal",     weight_grams: 5 },
    { caption: "Cartão de trivia",  weight_grams: 2 }
  ]

  if gotm.brindes.in_display_order.pluck(:caption) != brinde_kit.map { |b| b[:caption] } && File.exist?(placeholder_image)
    gotm.brindes.destroy_all
    brinde_kit.each_with_index do |attrs, index|
      brinde = gotm.brindes.build(attrs.merge(position: index))
      brinde.image.attach(
        io:           File.open(placeholder_image),
        filename:     "brinde-placeholder.jpg",
        content_type: "image/jpeg"
      )
      brinde.save!
    end
  end

  puts "Jogo do Mês: #{gotm.note} (#{gotm.year}-#{gotm.month}) — " \
       "#{gotm.products.count} produto(s), #{gotm.brindes.count} brinde(s)"
end
