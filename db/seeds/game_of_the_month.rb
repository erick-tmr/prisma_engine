# Jogo do Mês seed — idempotent.
#
# Empty by default. The editorial team curates the current month and any
# franchise picks; data lives in the database rather than this file so we
# don't have to ship a code change to update the homepage hero.
#
# Console snippet for setting (or updating) the current pick:
#
#   gotm = GameOfTheMonth.find_or_create_by!(year: 2026, month: 6) do |g|
#     g.note = "Especial Pokémon"
#   end
#   gotm.products << Product.find_by!(slug: "pokemon-yellow-version")
#   # The brinde's weight_grams feeds the shipping quote — a complete game
#   # + brindes lands around 80g per the cart spec, so a single brinde set
#   # is roughly 15g.
#   brinde = gotm.brindes.create!(caption: "Poster Pokémon", position: 0, weight_grams: 15)
#   brinde.image.attach(
#     io: File.open(Rails.root.join("public/images/brindes/poster.png")),
#     filename: "poster.png",
#     content_type: "image/png"
#   )
