require "base64"

module LinkPreview
  module Api
    class Asset
      include Client

      def self.fetch(url)
        new(url).fetch
      end

      def initialize(url)
        @url = url
      end

      def fetch
        return decode_data_uri if @url.start_with?("data:")

        response = raise_for_status(get(@url))
        {
          bytes:        response.body,
          content_type: response.headers["content-type"].presence || "image/x-icon"
        }
      end

      private

      def decode_data_uri
        meta, data = @url.delete_prefix("data:").split(",", 2)
        raise Error, "invalid data URI: #{@url}" if data.nil?

        {
          bytes:        meta.end_with?(";base64") ? Base64.decode64(data) : percent_decode(data),
          content_type: meta.delete_suffix(";base64").presence || "text/plain"
        }
      end

      def percent_decode(data)
        data.b.gsub(/%[0-9A-Fa-f]{2}/) { |match| match[1, 2].hex.chr }
      end
    end
  end
end
