module OpenGraphHelper
  SITE_NAME = "Prisma Games".freeze
  SITE_DESCRIPTION = "Prisma Games, especializada em desenvolvimento e produção de hardware " \
                     "para o Game Boy, da Nintendo.".freeze
  DEFAULT_IMAGE = "/images/prisma-games-logo.png".freeze
  IMAGE_WIDTH = 1200
  DESCRIPTION_LIMIT = 200

  def og_type
    content_for(:og_type).presence || "website"
  end

  def og_title
    content_for(:og_title).presence || content_for(:title).presence || SITE_NAME
  end

  def og_description
    content_for(:og_description).presence || content_for(:description).presence || SITE_DESCRIPTION
  end

  def og_image_url
    source = content_for(:og_image).presence || DEFAULT_IMAGE
    absolute_url(Storefront::CdnImage.transform(source, width: IMAGE_WIDTH))
  end

  # Spacing the tags out first keeps "</p><p>" from welding the last word of one
  # paragraph to the first of the next.
  def meta_description_from(html)
    spaced = html.to_s.gsub("<", " <")
    strip_tags(spaced).squish.truncate(DESCRIPTION_LIMIT, separator: " ").presence
  end
end
