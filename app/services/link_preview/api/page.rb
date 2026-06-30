module LinkPreview
  module Api
    class Page
      include Client

      def self.fetch(url)
        new(url).fetch
      end

      def initialize(url)
        @url = url
      end

      def fetch
        response = raise_for_status(get(@url))
        Metadata.parse(response.body, base_url: response.env.url.to_s)
      end
    end
  end
end
