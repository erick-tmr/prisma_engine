require "faraday"

module LinkPreview
  module Api
    module Client
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10
      MAX_REDIRECTS = 5
      REDIRECT_STATUSES = [ 301, 302, 303, 307, 308 ].freeze

      private

      def get(url)
        resolve_and_fetch(SafeUrl.call(url))
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
        raise TransientError, error.message
      end

      def resolve_and_fetch(url)
        current = url
        MAX_REDIRECTS.times do
          response = connection.get(current)
          location = response.headers["location"]
          return response unless REDIRECT_STATUSES.include?(response.status) && location.present?

          current = SafeUrl.call(URI.join(current, location).to_s)
        end
        raise Error, "too many redirects for #{current}"
      end

      def connection
        @connection ||= Faraday.new do |conn|
          conn.options.open_timeout = OPEN_TIMEOUT
          conn.options.timeout = READ_TIMEOUT
          conn.headers["User-Agent"] = USER_AGENT
          conn.adapter Faraday.default_adapter
        end
      end

      def raise_for_status(response, ok: [ 200 ])
        status = response.status
        return response if ok.include?(status)
        raise TransientError, "link preview returned #{status}" if status == 429 || status >= 500

        raise Error, "link preview returned #{status}"
      end
    end
  end
end
