module Recommendations
  module Refresh
    module_function

    FAVICON_EXTENSIONS = {
      "image/png"       => "png",
      "image/jpeg"      => "jpg",
      "image/gif"       => "gif",
      "image/webp"      => "webp",
      "image/svg+xml"   => "svg",
      "image/x-icon"    => "ico",
      "image/vnd.microsoft.icon" => "ico"
    }.freeze

    def call(recommendation)
      preview = LinkPreview::Api::Page.fetch(recommendation.url)
      recommendation.title   = preview[:title].presence       || recommendation.title
      recommendation.tagline = preview[:description].presence || recommendation.tagline
      attach_favicon(recommendation, preview[:favicon_url])
      recommendation.fetched_at = Time.current
      recommendation.save!
    end

    def call_all
      Recommendation.find_each do |recommendation|
        call(recommendation)
      rescue LinkPreview::Api::Error => error
        Rails.logger.warn("[Recommendations::Refresh] #{recommendation.url}: #{error.message}")
      end
    end

    def attach_favicon(recommendation, favicon_url)
      asset = LinkPreview::Api::Asset.fetch(favicon_url)
      recommendation.favicon.attach(
        io: StringIO.new(asset[:bytes]),
        filename: "favicon.#{FAVICON_EXTENSIONS.fetch(asset[:content_type], "ico")}",
        content_type: asset[:content_type]
      )
    rescue LinkPreview::Api::Error => error
      Rails.logger.warn("[Recommendations::Refresh] favicon #{favicon_url}: #{error.message}")
    end
  end
end
