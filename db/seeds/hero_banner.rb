# Hero banner seed — idempotent. The homepage hero is stored on R2 via Active
# Storage so editorial can swap it through the console (or a future admin)
# without a deploy. Only bootstraps when no banner exists yet; re-seeding never
# duplicates it.
if HeroBanner.none?
  banner = HeroBanner.new(alt: "Prisma Games", position: 0)
  banner.image.attach(
    io:           File.open(Rails.root.join("db/seeds/hero_banner.jpg")),
    filename:     "hero-banner.jpg",
    content_type: "image/jpeg"
  )
  banner.save!

  puts "Hero banner: #{HeroBanner.count} ativo(s)"
end
