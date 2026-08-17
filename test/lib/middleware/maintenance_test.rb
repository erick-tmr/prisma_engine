require "test_helper"
require Rails.root.join("lib/middleware/maintenance")

module Middleware
  class MaintenanceTest < ActiveSupport::TestCase
    PAGE_PATH = Rails.root.join("public/maintenance.html")
    IMAGE_HOST = "https://cdn.example.test".freeze

    setup do
      @downstream_calls = []
      downstream = ->(env) {
        @downstream_calls << env
        [ 200, { "content-type" => "text/plain" }, [ "ok" ] ]
      }
      @middleware = Middleware::Maintenance.new(
        downstream,
        page_path: PAGE_PATH,
        image_host: "#{IMAGE_HOST}/",
        allowed_ips: [ "203.0.113.7" ],
        passthrough: [ %r{\A/up\z}, %r{\A/pagamentos/webhook/} ]
      )
    end

    test "closes the storefront with a 503 and the maintenance page" do
      status, headers, body = call("https://prismagames.com.br/produtos")

      assert_equal 503, status
      assert_equal "text/html; charset=utf-8", headers["content-type"]
      assert_equal "no-store", headers["cache-control"]
      assert_includes body.first, "Voltamos já"
      assert_empty @downstream_calls
    end

    test "sends retry-after so search engines wait instead of deindexing" do
      _status, headers, body = call("https://prismagames.com.br/")

      assert_equal "600", headers["retry-after"]
      assert_equal body.first.bytesize.to_s, headers["content-length"]
    end

    test "points the page's images at the environment's own bucket host" do
      _status, _headers, body = call("https://prismagames.com.br/")
      page = body.first

      assert_includes page, "#{IMAGE_HOST}/maintenance/guard.png"
      assert_includes page, "#{IMAGE_HOST}/emails/prisma-games-logo.png"
      assert_not_includes page, Middleware::Maintenance::IMAGE_HOST_PLACEHOLDER
      assert_not_includes page, "#{IMAGE_HOST}//", "a trailing slash on the host would double up"
    end

    test "the page depends on nothing the gate blocks" do
      page = File.read(PAGE_PATH)

      assert_not_includes page, "/images/",
        "local asset requests would be answered with the maintenance page itself"
      assert_not_includes page, "<script src",
        "an external script would never load while the gate is closed"
    end

    test "lets the healthcheck through so kamal-proxy keeps the container in rotation" do
      status, _headers, body = call("http://127.0.0.1/up")

      assert_equal 200, status
      assert_equal [ "ok" ], body
      assert_equal 1, @downstream_calls.size
    end

    test "lets the payment webhook through so a payment mid-window still confirms" do
      status, _headers, _body = call(
        "https://prismagames.com.br/pagamentos/webhook/abc123", method: "POST"
      )

      assert_equal 200, status
      assert_equal 1, @downstream_calls.size
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
