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
#   brinde = gotm.brindes.create!(caption: "Poster Pokémon", position: 0)
#   brinde.image.attach(
#     io: File.open(Rails.root.join("public/images/brindes/poster.png")),
#     filename: "poster.png",
#     content_type: "image/png"
#   )
