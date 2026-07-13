module StorefrontImageHelper
  PRESETS = {
    hero: { widths: [ 640, 1024, 1288, 1920 ], sizes: "(max-width: 1320px) 100vw, 1288px" },
    gotm: { widths: [ 640, 1024, 1288 ],       sizes: "(max-width: 1320px) 100vw, 1288px" },
    card: { widths: [ 320, 480, 640 ],         sizes: "(min-width: 768px) 320px, 50vw" }
  }.freeze

  def storefront_image_tag(src, preset: nil, resize: nil, **options)
    if Storefront::CdnImage.transformable?(src)
      if preset
        widths, sizes = PRESETS.fetch(preset).values_at(:widths, :sizes)
        options[:srcset] = Storefront::CdnImage.srcset(src, widths:)
        options[:sizes] = sizes
        src = Storefront::CdnImage.transform(src, width: widths.max)
      elsif resize
        src = Storefront::CdnImage.transform(src, width: resize)
      end
    end
    tag.img(src:, **options)
  end

  def hero_preload_link(src)
    return "".html_safe unless Storefront::CdnImage.transformable?(src)

    widths, sizes = PRESETS.fetch(:hero).values_at(:widths, :sizes)
    tag.link(rel: "preload", as: "image",
             imagesrcset: Storefront::CdnImage.srcset(src, widths:),
             imagesizes: sizes, fetchpriority: "high")
  end
end
