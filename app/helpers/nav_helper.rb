module NavHelper
  SOCIAL_LINKS = {
    whatsapp: "https://wa.me/5535920001100",
    instagram: "https://instagram.com/prisma.games"
  }.freeze

  def self.whatsapp_url(message)
    "#{SOCIAL_LINKS.fetch(:whatsapp)}?text=#{CGI.escape(message)}"
  end

  def social_links
    SOCIAL_LINKS
  end

  def nav_recommendations
    @nav_recommendations ||= Recommendation.active.in_display_order.to_a
  end
end
