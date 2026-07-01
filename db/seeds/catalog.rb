# Catalog seed — idempotent.
#
# config/products.yml is the single source of the real catalog (curated slugs,
# titles, prices, images). It is intentionally retained as a one-time seed
# source: nothing loads it at runtime now that Product is an AR model. A later
# slice can migrate this ingest into a proper admin import and drop the YAML.

require "bigdecimal"

# --- Categories (consoles) -------------------------------------------------
category_by_slug = {
  "game-boy-classic" => "Game Boy Classic",
  "game-boy-color"   => "Game Boy Color",
  # Game Boy Advance has no products yet — seeded for the near-future catalog.
  "game-boy-advance" => "Game Boy Advance",
  "pedidos-de-jogos" => "Pedidos de Jogos",
  "miscelanea"       => "Extras & Acessórios"
}.to_h do |slug, name|
  category = Category.find_or_create_by!(slug: slug) { |c| c.name = name }
  category.update!(name: name) unless category.name == name
  [ slug, category ]
end

# --- Products --------------------------------------------------------------
def attach_photos(product, image_paths)
  files = image_paths.filter_map do |path|
    file = Rails.root.join("public", path.to_s.delete_prefix("/"))
    file if File.exist?(file)
  end
  return if files.empty?

  files.each_with_index do |file, index|
    photo = product.product_photos.in_display_order.to_a[index] ||
            product.product_photos.new(position: index)
    unless photo.image.attached? && photo.image.blob.checksum == OpenSSL::Digest::MD5.file(file).base64digest
      photo.image.purge if photo.image.attached?
      photo.image.attach(io: File.open(file), filename: File.basename(file), content_type: "image/jpeg")
    end
    photo.update!(position: index, alt_text: product.name)
  end

  product.product_photos.where(position: files.size..).destroy_all
end

def infer_tag_slugs(name)
  slugs = []
  slugs << "pokemon" if name.match?(/pokemon/i)
  slugs << "zelda"   if name.match?(/zelda/i)
  slugs << "rpg"     if name.match?(/pokemon|zelda/i)
  slugs << "rtc"     if name.match?(/\bRTC\b/i)
  slugs << "romhack" if name.match?(/romhack|\bhack\b/i)
  slugs.uniq
end

def build_options(entry, default_languages)
  groups = [ [ "Idioma", entry["languages"] || default_languages ] ]
  Array(entry["options"]).each do |group|
    groups << [ group["group"], Array(group["values"]) ]
  end

  position = -1
  groups.flat_map do |group_name, values|
    Array(values).map do |value|
      position += 1
      { group_name: group_name, name: value, weight_delta_grams: 0, position: position }
    end
  end
end

default_languages = [ "Português BR", "Inglês", "Japonês" ]

default_description = <<~TEXT.strip
  Cartucho reproduzido pela Prisma Games, no Brasil, com placa própria (Prisma v0.6) testada uma a uma. O save fica gravado em memória FRAM, que não precisa de bateria, e seu progresso dura por anos, sem risco de perder os arquivos.

  Já vem completo, com estojo rígido e etiqueta em padrão US, compatível com a linha Game Boy. Você escolhe o idioma da ROM nas opções acima, e cada unidade é testada individualmente antes do envio.
TEXT

raw = YAML.safe_load_file(Rails.root.join("config/products.yml"))
raw.fetch("products").each do |entry|
  category = category_by_slug.fetch(entry["category"])

  image_paths = entry["images"] || Array(entry["image"])

  product = Product.find_or_initialize_by(slug: entry["slug"])
  product.assign_attributes(
    name:              CGI.unescapeHTML(entry["title"]),
    category:          category,
    price_cents:       (BigDecimal(entry["price_brl"].to_s) * 100).to_i,
    currency:          "BRL",
    published:         true,
    weight_grams:      60,
    legacy_image_path: image_paths.first
  )
  if entry.key?("description")
    product.description = entry["description"].to_s
  elsif product.description.blank?
    product.description = default_description
  end
  product.save!

  product_options = build_options(entry, default_languages)
  product_options.each do |attrs|
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

  kept = product_options.map { |attrs| [ attrs[:group_name], attrs[:name] ] }
  product.product_options.reload.each do |option|
    option.destroy unless kept.include?([ option.group_name, option.name ])
  end

  infer_tag_slugs(product.name).each do |tag_slug|
    tag = Tag.find_or_create_by!(name: tag_slug)
    ProductTag.find_or_create_by!(product: product, tag: tag)
  end

  attach_photos(product, image_paths)
end

# --- Extras & Acessórios (standalone parts) --------------------------------
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

  attach_photos(product, Array(attrs[:image]))
end

puts "Seeded: #{Category.count} categories, #{Product.count} products, " \
     "#{ProductOption.count} options, #{Tag.count} tags, " \
     "#{ProductPhoto.count} photos"
