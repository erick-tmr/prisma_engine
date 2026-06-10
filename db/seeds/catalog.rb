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
  "game-boy-advance" => { name: "Game Boy Advance" }
}.transform_values do |attrs|
  Category.find_or_create_by!(slug: attrs.fetch(:name).parameterize) do |c|
    c.name = attrs[:name]
  end
end

category_by_slug = {
  "game-boy-classic" => categories["game-boy-classic"],
  "game-boy-color"   => categories["game-boy-color"]
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

# Default option set seeded on every product. Price deltas are 0: the mechanism
# is proven without inventing prices not present in the source data. Weight
# deltas follow the spec — "Com caixa" adds the 38g caixa + berço; everything
# else matches the base PCB+shell weight (22g) and stays at 0.
default_options = [
  { group_name: "Idioma", name: "Português BR", price_delta_cents: 0, weight_delta_grams: 0,  position: 0 },
  { group_name: "Idioma", name: "Inglês",       price_delta_cents: 0, weight_delta_grams: 0,  position: 1 },
  { group_name: "Idioma", name: "Japonês",      price_delta_cents: 0, weight_delta_grams: 0,  position: 2 },
  { group_name: "Caixa",  name: "Com caixa",    price_delta_cents: 0, weight_delta_grams: 38, position: 3 },
  { group_name: "Caixa",  name: "Sem caixa",    price_delta_cents: 0, weight_delta_grams: 0,  position: 4 }
]

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
    weight_grams:      22, # PCB + shell baseline; cart adds 38g when "Com caixa" is selected.
    legacy_image_path: entry["image"]
  )
  product.save!

  default_options.each do |attrs|
    option = ProductOption.find_or_initialize_by(
      product:    product,
      group_name: attrs[:group_name],
      name:       attrs[:name]
    )
    option.assign_attributes(
      price_delta_cents:  attrs[:price_delta_cents],
      weight_delta_grams: attrs[:weight_delta_grams],
      position:           attrs[:position]
    )
    option.save!
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

puts "Seeded: #{Category.count} categories, #{Product.count} products, " \
     "#{ProductOption.count} options, #{Tag.count} tags, " \
     "#{ProductPhoto.count} photos"
