require "nokogiri"

module LinkPreview
  module Api
    module Metadata
      module_function

      def parse(html, base_url:)
        doc = Nokogiri::HTML(html)
        {
          title:       title(doc),
          description: description(doc),
          favicon_url: favicon_url(doc, base_url)
        }
      end

      def title(doc)
        text = doc.at_css("title")&.text
        text = doc.at_css('meta[property="og:title"]')&.[]("content") if text.blank?
        text.presence&.strip
      end

      def description(doc)
        text = doc.at_css('meta[name="description"]')&.[]("content")
        text = doc.at_css('meta[property="og:description"]')&.[]("content") if text.blank?
        text.presence&.strip
      end

      def favicon_url(doc, base_url)
        href = icon_href(doc)
        return href if href.start_with?("data:")

        URI.join(base_url, href).to_s
      rescue URI::InvalidURIError
        URI.join(base_url, "/favicon.ico").to_s
      end

      def icon_href(doc)
        link = doc.at_css('link[rel~="apple-touch-icon"]') || doc.at_css('link[rel~="icon"]')
        link&.[]("href").presence || "/favicon.ico"
      end
    end
  end
end
