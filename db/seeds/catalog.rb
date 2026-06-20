# Catalog seed — idempotent.
#
# config/products.yml is the single source of the real catalog (curated slugs,
# titles, prices, images). It is intentionally retained as a one-time seed
# source: nothing loads it at runtime now that Product is an AR model. A later
# slice can migrate this ingest into a proper admin import and drop the YAML.

require "bigdecimal"

# --- Categories (consoles) -------------------------------------------------
categories = {
  "game-boy-classic" => { name: "Game Boy Classic" },
  "game-boy-color"   => { name: "Game Boy Color" },
  # Game Boy Advance has no products yet — seeded for the near-future catalog.
  "game-boy-advance" => { name: "Game Boy Advance" },
  "miscelanea"       => { name: "Miscelânea" }
}.transform_values do |attrs|
  Category.find_or_create_by!(slug: attrs.fetch(:name).parameterize) do |c|
    c.name = attrs[:name]
  end
end

category_by_slug = {
  "game-boy-classic" => categories["game-boy-classic"],
  "game-boy-color"   => categories["game-boy-color"],
  "miscelanea"       => categories["miscelanea"]
}

# --- Products --------------------------------------------------------------
def infer_tag_slugs(name)
  slugs = []
  slugs << "pokemon" if name.match?(/pokemon/i)
  slugs << "zelda"   if name.match?(/zelda/i)
  slugs << "rpg"     if name.match?(/pokemon|zelda/i)
  slugs << "rtc"     if name.match?(/\bRTC\b/i)
  slugs << "romhack" if name.match?(/romhack|\bhack\b/i)
  slugs.uniq
end

default_options = [
  { group_name: "Idioma", name: "Português BR", weight_delta_grams: 0, position: 0 },
  { group_name: "Idioma", name: "Inglês",       weight_delta_grams: 0, position: 1 },
  { group_name: "Idioma", name: "Japonês",      weight_delta_grams: 0, position: 2 }
]
kept_options = default_options.map { |attrs| [ attrs[:group_name], attrs[:name] ] }

default_description = <<~TEXT.strip
  Cartucho reproduzido pela Prisma Games, no Brasil, com placa própria (Prisma v0.6) testada uma a uma. O save fica gravado em memória FRAM, que não precisa de bateria, e seu progresso dura por anos, sem risco de perder os arquivos.

  Já vem completo, com estojo rígido e etiqueta em padrão US, compatível com a linha Game Boy. Você escolhe o idioma da ROM nas opções acima, e cada unidade é testada individualmente antes do envio.
TEXT

raw = YAML.safe_load_file(Rails.root.join("config/products.yml"))
raw.fetch("products").each do |entry|
  category = category_by_slug.fetch(entry["category"])

  product = Product.find_or_initialize_by(slug: entry["slug"])
  product.assign_attributes(
    name:              CGI.unescapeHTML(entry["title"]),
    category:          category,
    price_cents:       (BigDecimal(entry["price_brl"].to_s) * 100).to_i,
    currency:          "BRL",
    published:         true,
    weight_grams:      60,
    legacy_image_path: entry["image"]
  )
  product.description = default_description if product.description.blank?
  product.save!

  default_options.each do |attrs|
    option = ProductOption.find_or_initialize_by(
      product:    product,
      group_name: attrs[:group_name],
      name:       attrs[:name]
    )
    option.assign_attributes(
      weight_delta_grams: attrs[:weight_delta_grams],
      position:           attrs[:position]
    )
    option.save!
  end

  product.product_options.reload.each do |option|
    option.destroy unless kept_options.include?([ option.group_name, option.name ])
  end

  infer_tag_slugs(product.name).each do |tag_slug|
    tag = Tag.find_or_create_by!(name: tag_slug)
    ProductTag.find_or_create_by!(product: product, tag: tag)
  end

  # Attach the vendored image as a ProductPhoto; Product#image falls back to
  # legacy_image_path so a missing file never breaks seeding or the storefront.
  if product.legacy_image_path.present? && product.product_photos.empty?
    file = Rails.root.join("public", product.legacy_image_path.delete_prefix("/"))
    if File.exist?(file)
      photo = product.product_photos.create!(alt_text: product.name, position: 0)
      photo.image.attach(
        io:           File.open(file),
        filename:     File.basename(file),
        content_type: "image/jpeg"
      )
    end
  end
end

# --- Miscelânea (standalone parts) -----------------------------------------
misc_products = [
  { slug: "carcaca-de-plastico", name: "Carcaça de plástico", price_cents: 2000, weight_grams: 38,
    image: "/images/stores/uploads/6305129/conversions/large.jpg",
    description: "Case de plástico para guardar e proteger o seu cartucho de Game Boy." },
  { slug: "caixa-estojo-do-jogo", name: "Caixa (estojo do jogo)", price_cents: 2500, weight_grams: 30,
    description: "Estojo do jogo no padrão da linha Game Boy." },
  { slug: "etiqueta-label-us", name: "Etiqueta (label US)", price_cents: 1000, weight_grams: 2,
    description: "Etiqueta (label) em padrão US para o seu cartucho." }
]

misc_products.each do |attrs|
  product = Product.find_or_initialize_by(slug: attrs[:slug])
  product.assign_attributes(
    name:              attrs[:name],
    category:          category_by_slug.fetch("miscelanea"),
    price_cents:       attrs[:price_cents],
    currency:          "BRL",
    published:         true,
    weight_grams:      attrs[:weight_grams],
    legacy_image_path: attrs[:image],
    description:       attrs[:description]
  )
  product.save!

  if product.legacy_image_path.present? && product.product_photos.empty?
    file = Rails.root.join("public", product.legacy_image_path.delete_prefix("/"))
    if File.exist?(file)
      photo = product.product_photos.create!(alt_text: product.name, position: 0)
      photo.image.attach(
        io:           File.open(file),
        filename:     File.basename(file),
        content_type: "image/jpeg"
      )
    end
  end
end

puts "Seeded: #{Category.count} categories, #{Product.count} products, " \
     "#{ProductOption.count} options, #{Tag.count} tags, " \
     "#{ProductPhoto.count} photos"
