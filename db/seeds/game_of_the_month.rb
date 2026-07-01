game = Product.find_by(slug: "shantae")

if game
  gotm = GameOfTheMonth.find_or_initialize_by(year: Date.current.year, month: Date.current.month)
  gotm.note = "Shantae" if gotm.new_record?
  gotm.save!

  GameOfTheMonthProduct.find_or_create_by!(game_of_the_month: gotm, product: game) do |gp|
    gp.position = 0
  end

  placeholder_image = Rails.root.join("public/images/stores/uploads/2475313/conversions/large.jpg")

  if gotm.brindes.none? && File.exist?(placeholder_image)
    [
      { caption: "Adesivo Shantae",            weight_grams: 8, position: 0 },
      { caption: "Cartela de cards exclusiva", weight_grams: 7, position: 1 }
    ].each do |attrs|
      brinde = gotm.brindes.build(attrs)
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
