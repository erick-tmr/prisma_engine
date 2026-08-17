require "test_helper"
require Rails.root.join("lib/middleware/maintenance")

module Middleware
  class MaintenanceTest < ActiveSupport::TestCase
    PAGE_PATH = Rails.root.join("public/maintenance.html")

    setup do
      @downstream_calls = []
      downstream = ->(env) {
        @downstream_calls << env
        [ 200, { "content-type" => "text/plain" }, [ "ok" ] ]
      }
      @middleware = Middleware::Maintenance.new(
        downstream,
        page_path: PAGE_PATH,
        allowed_ips: [ "203.0.113.7" ],
        passthrough: [ %r{\A/up\z}, %r{\A/pagamentos/webhook/}, %r{\A/images/} ]
      )
    end

    test "closes the storefront with a 503 and the maintenance page" do
      status, headers, body = call("https://prismagames.com.br/produtos")

      assert_equal 503, status
      assert_equal [ File.read(PAGE_PATH) ], body
      assert_equal "text/html; charset=utf-8", headers["content-type"]
      assert_equal "no-store", headers["cache-control"]
      assert_empty @downstream_calls
    end

    test "sends retry-after so search engines wait instead of deindexing" do
      _status, headers, _body = call("https://prismagames.com.br/")

      assert_equal "600", headers["retry-after"]
      assert_equal File.size(PAGE_PATH).to_s, headers["content-length"]
    end

    test "lets the healthcheck through so kamal-proxy keeps the container in rotation" do
      status, _headers, body = call("http://127.0.0.1/up")

      assert_equal 200, status
      assert_equal [ "ok" ], body
      assert_equal 1, @downstream_calls.size
    end

    test "lets the payment webhook through so a payment mid-window still enqueues" do
      status, _headers, _body = call(
        "https://prismagames.com.br/pagamentos/webhook/abc123", method: "POST"
      )

      assert_equal 200, status
      assert_equal 1, @downstream_calls.size
    end

    test "lets public images through so the maintenance page renders its own art" do
      status, _headers, _body = call("https://prismagames.com.br/images/prisma-games-logo.png")

      assert_equal 200, status
      assert_equal 1, @downstream_calls.size
    end

    test "the assets the maintenance page references are actually present" do
      page = File.read(PAGE_PATH)

      page.scan(%r{src="(/images/[^"]+)"}).flatten.each do |path|
        assert_path_exists Rails.root.join("public#{path}")
      end
    end

    test "lets an allowed operator through by the Cloudflare client IP header" do
      status, _headers, _body = call(
        "https://prismagames.com.br/carrinho", headers: { "HTTP_CF_CONNECTING_IP" => "203.0.113.7" }
      )

      assert_equal 200, status
      assert_equal 1, @downstream_calls.size
    end

    test "falls back to the socket address when the Cloudflare header is absent" do
      status, _headers, _body = call(
        "https://prismagames.com.br/carrinho", headers: { "REMOTE_ADDR" => "203.0.113.7" }
      )

      assert_equal 200, status
      assert_equal 1, @downstream_calls.size
    end

    test "closes the storefront for a client that is not on the allow list" do
      status, _headers, _body = call(
        "https://prismagames.com.br/carrinho", headers: { "HTTP_CF_CONNECTING_IP" => "198.51.100.4" }
      )

      assert_equal 503, status
      assert_empty @downstream_calls
    end

    private

    def call(url, method: "GET", headers: {})
      @middleware.call(Rack::MockRequest.env_for(url, method: method).merge(headers))
    end
  end
end
