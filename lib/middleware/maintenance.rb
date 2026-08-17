module Middleware
  class Maintenance
    RETRY_AFTER = "600".freeze

    IMAGE_HOST_PLACEHOLDER = "{{IMAGE_HOST}}".freeze

    def initialize(app, page_path:, image_host:, allowed_ips: [], passthrough: [])
      @app = app
      @page_path = page_path
      @image_host = image_host.to_s.chomp("/")
      @allowed_ips = allowed_ips
      @passthrough = passthrough
    end

    def call(env)
      request = Rack::Request.new(env)
      return @app.call(env) if passthrough?(request) || allowed_ip?(request)

      [ 503, headers, [ page ] ]
    end

    private

    def passthrough?(request)
      @passthrough.any? { |pattern| pattern.match?(request.path) }
    end

    def allowed_ip?(request)
      @allowed_ips.include?(client_ip(request))
    end

    def client_ip(request)
      request.get_header("HTTP_CF_CONNECTING_IP").presence || request.ip
    end

    def headers
      {
        "content-type" => "text/html; charset=utf-8",
        "content-length" => page.bytesize.to_s,
        "cache-control" => "no-store",
        "retry-after" => RETRY_AFTER
      }
    end

    def page
      @page ||= File.read(@page_path).gsub(IMAGE_HOST_PLACEHOLDER, @image_host)
    end
  end
end
