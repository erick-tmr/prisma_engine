module Storefront
  module CdnImage
    module_function

    DEFAULT_QUALITY = 78

    def enabled?
      Rails.application.config.x.cdn_image_transforms.present?
    end

    def host
      Rails.application.config.x.r2_public_host.to_s.chomp("/")
    end

    def transformable?(url)
      enabled? && host.present? && url.to_s.start_with?(host) && !url.to_s.end_with?(".svg")
    end

    def transform(url, width:, quality: DEFAULT_QUALITY)
      return url unless transformable?(url)

      options = "width=#{width},quality=#{quality},format=auto,fit=scale-down,metadata=none,onerror=redirect"
      "#{host}/cdn-cgi/image/#{options}#{url.delete_prefix(host)}"
    end

    def srcset(url, widths:, quality: DEFAULT_QUALITY)
      widths.map { |width| "#{transform(url, width:, quality:)} #{width}w" }.join(", ")
    end
  end
end
