# Jogo do Mês seed — idempotent.
#
# Bootstraps Metal Gear as the current month's Jogo do Mês with two placeholder
# brindes whose weights sum to 15g (the per-line brindes mass the cart spec
# targets: a complete game + brindes ≈ 75g). Editorial replaces the brinde
# images + captions via the console (or a future admin) once the real shoot
# is ready.
#
# Console snippet for setting up *another* month later (e.g. franchise picks):
#
#   gotm = GameOfTheMonth.find_or_create_by!(year: 2026, month: 7) do |g|
#     g.note = "Especial Pokémon"
#   end
#   gotm.products << Product.find_by!(slug: "pokemon-yellow-version")
#   brinde = gotm.brindes.create!(caption: "Poster Pokémon", position: 0, weight_grams: 15)
#   brinde.image.attach(
#     io: File.open(Rails.root.join("public/images/brindes/poster.png")),
#     filename: "poster.png",
#     content_type: "image/png"
#   )

metal_gear = Product.find_by(slug: "metal-gear-solid-jogo-do-mes")

if metal_gear
  gotm = GameOfTheMonth.find_or_initialize_by(year: Date.current.year, month: Date.current.month)
  gotm.note = "Metal Gear" if gotm.new_record?
  gotm.save!

  GameOfTheMonthProduct.find_or_create_by!(game_of_the_month: gotm, product: metal_gear) do |gp|
    gp.position = 0
  end

  # Brindes only get bootstrapped on a fresh GOTM. We don't add to an existing
  # set — editorial may have already curated the real ones and we'd otherwise
  # silently double them up on every re-seed.
  placeholder_image = Rails.root.join("public/images/stores/uploads/2475313/conversions/large.jpg")

  if gotm.brindes.none? && File.exist?(placeholder_image)
    [
      { caption: "Adesivo Metal Gear",         weight_grams: 8, position: 0 },
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
