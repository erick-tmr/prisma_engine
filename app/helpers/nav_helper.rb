module NavHelper
  SOCIAL_LINKS = {
    whatsapp: "https://wa.me/5535920001100",
    instagram: "https://instagram.com/prisma.games"
  }.freeze

  def social_links
    SOCIAL_LINKS
  end

  def nav_partners
    NavHelper.partners
  end

  def self.partners
    @partners ||= YAML.safe_load_file(Rails.root.join("config", "partners.yml"))
                      .fetch("partners", [])
                      .map { |attrs| attrs.transform_keys(&:to_sym).freeze }
                      .freeze
  end
end
