# Hero banner seed: idempotent. The homepage hero is stored on R2 via Active
# Storage so editorial can swap it through the console (or a future admin)
# without a deploy. Only bootstraps when no banner exists yet; re-seeding never
# duplicates it.
hero_image = Rails.root.join("db/seeds/hero_banner.jpg")
if HeroBanner.none? && File.exist?(hero_image)
  banner = HeroBanner.new(alt: "Prisma Games", position: 0)
  banner.image.attach(
    io:           File.open(hero_image),
    filename:     "hero-banner.jpg",
    content_type: "image/jpeg"
  )
  banner.save!

  puts "Hero banner: #{HeroBanner.count} ativo(s)"
end
