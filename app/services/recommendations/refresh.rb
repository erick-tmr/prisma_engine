require "base64"

module Recommendations
  module Refresh
    module_function

    def call(recommendation)
      preview = LinkPreview::Api::Page.fetch(recommendation.url)
      recommendation.title   = preview[:title].presence       || recommendation.title
      recommendation.tagline = preview[:description].presence || recommendation.tagline
      recommendation.favicon_data_uri = fetch_favicon_data_uri(preview[:favicon_url]) || recommendation.favicon_data_uri
      recommendation.fetched_at = Time.current
      recommendation.save!
    end

    def fetch_favicon_data_uri(favicon_url)
      asset = LinkPreview::Api::Asset.fetch(favicon_url)
      "data:#{asset[:content_type]};base64,#{Base64.strict_encode64(asset[:bytes])}"
    rescue LinkPreview::Api::Error => error
      Rails.logger.warn("[Recommendations::Refresh] favicon #{favicon_url}: #{error.message}")
      nil
    end
  end
end
