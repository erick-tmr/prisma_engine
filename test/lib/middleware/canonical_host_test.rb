require "test_helper"
require Rails.root.join("lib/middleware/canonical_host")

module Middleware
  class CanonicalHostTest < ActiveSupport::TestCase
    setup do
      @downstream_calls = []
      downstream = ->(env) {
        @downstream_calls << env
        [ 200, { "content-type" => "text/plain" }, [ "ok" ] ]
      }
      @middleware = Middleware::CanonicalHost.new(
        downstream, from: "www.prismagames.com.br", to: "prismagames.com.br"
      )
    end

    test "serves the canonical host without redirecting" do
      status, _headers, body = call("https://prismagames.com.br/minha-conta/pedidos/PG-39219")

      assert_equal 200, status
      assert_equal [ "ok" ], body
      assert_equal 1, @downstream_calls.size
    end

    test "leaves unrelated hosts alone so the container healthcheck still reaches the app" do
      status, _headers, _body = call("http://127.0.0.1/up")

      assert_equal 200, status
      assert_equal 1, @downstream_calls.size
    end

    test "redirects the www host to the canonical one, keeping path and query" do
      status, headers, _body = call("https://www.prismagames.com.br/produtos?busca=game+boy&page=2")

      assert_equal 301, status
      assert_equal "https://prismagames.com.br/produtos?busca=game+boy&page=2", headers["location"]
      assert_empty @downstream_calls
    end

    test "redirects the order link that arrives from an email" do
      _status, headers, _body = call("https://www.prismagames.com.br/minha-conta/pedidos/PG-39219")

      assert_equal "https://prismagames.com.br/minha-conta/pedidos/PG-39219", headers["location"]
    end

    test "keeps the request scheme so it does not downgrade or force a second hop" do
      _status, headers, _body = call("http://www.prismagames.com.br/")

      assert_equal "http://prismagames.com.br/", headers["location"]
    end

    private

    def call(url)
      @middleware.call(Rack::MockRequest.env_for(url))
    end
  end
end
