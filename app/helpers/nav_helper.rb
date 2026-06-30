module NavHelper
  SOCIAL_LINKS = {
    whatsapp: "https://wa.me/5535920001100",
    instagram: "https://instagram.com/prisma.games"
  }.freeze

  def social_links
    SOCIAL_LINKS
  end

  def nav_recommendations
    Recommendation.active.in_display_order
  end
end
