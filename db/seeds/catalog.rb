# Catalog seed — idempotent.
#
# config/products.yml is the single source of the real SKUs (curated slugs,
# titles, prices, images). It is intentionally retained as a one-time seed
# source: nothing loads it at runtime now that Product is an AR model. A later
# slice can migrate this ingest into a proper admin import and drop the YAML.

require "bigdecimal"

# --- Categories (consoles) -------------------------------------------------
categories = {
  "game-boy-classic" => { name: "Game Boy Classic", position: 0 },
  "game-boy-color"   => { name: "Game Boy Color",   position: 1 },
  # Game Boy Advance has no products yet — seeded for the near-future catalog.
  "game-boy-advance" => { name: "Game Boy Advance", position: 2 }
}.transform_values do |attrs|
  Category.find_or_create_by!(slug: attrs.fetch(:name).parameterize) do |c|
    c.name     = attrs[:name]
    c.position = attrs[:position]
  end
end

category_by_slug = {
  "game-boy-classic" => categories["game-boy-classic"],
  "game-boy-color"   => categories["game-boy-color"]
}

# --- Global option types ---------------------------------------------------
# Contributions are 0: the mechanism is proven without inventing prices that
# are not present in the source data. Real pricing lands when Vinicius supplies
# per-product schemas.
option_data = {
  "Idioma" => [ "Português BR", "Inglês", "Japonês" ],
  "Caixa"  => [ "Com caixa", "Sem caixa" ]
}
option_data.each do |type_name, value_names|
  type = OptionType.find_or_create_by!(slug: type_name.parameterize) do |ot|
    ot.name = type_name
  end
  value_names.each_with_index do |value_name, idx|
    OptionValue.find_or_create_by!(option_type: type, name: value_name) do |ov|
      ov.price_contribution_cents = 0
      ov.position = idx
    end
  end
end

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

raw = YAML.safe_load_file(Rails.root.join("config/products.yml"))
raw.fetch("products").each_with_index do |entry, index|
  category = category_by_slug.fetch(entry["category"])

  product = Product.find_or_initialize_by(slug: entry["slug"])
  product.assign_attributes(
    name:              CGI.unescapeHTML(entry["title"]),
    category:          category,
    price_cents:       (BigDecimal(entry["price_brl"].to_s) * 100).to_i,
    currency:          "BRL",
    published:         true,
    position:          index,
    legacy_image_path: entry["image"],
    legacy_short_id:   entry["short_id"]
  )
  product.save!

  # Master variant: the SKU a product falls back to when no options are chosen.
  Variant.find_or_create_by!(product: product, is_master: true) do |v|
    v.sku         = "PG-#{entry['short_id']}"
    v.price_cents = product.price_cents
    v.available   = true
    v.position    = 0
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
     "#{Variant.count} variants, #{Tag.count} tags, " \
     "#{ProductPhoto.count} photos"
