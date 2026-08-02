module Middleware
  class CanonicalHost
    def initialize(app, from:, to:)
      @app = app
      @from = from
      @to = to
    end

    def call(env)
      request = Rack::Request.new(env)
      return @app.call(env) unless request.host == @from

      [ 301, { "location" => canonical_url(request), "content-type" => "text/plain" }, [] ]
    end

    private

    def canonical_url(request)
      "#{request.scheme}://#{@to}#{request.fullpath}"
    end
  end
end
