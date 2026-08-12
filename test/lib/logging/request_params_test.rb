require "test_helper"
require Rails.root.join("lib/logging/request_params")

module Logging
  class RequestParamsTest < ActiveSupport::TestCase
    test "logs the whole body of a write" do
      params = call(post("/checkout/endereco", address: { zip: "37500100", number: "45" }))

      assert_equal({ "address" => { "zip" => "37500100", "number" => "45" } }, params)
    end

    test "keeps the customer's own data readable" do
      params = call(post("/", user: { email: "a@b.com", cpf: "39053344705", phone: "(11) 98765-4321" }))

      assert_equal({ "email" => "a@b.com", "cpf" => "39053344705", "phone" => "(11) 98765-4321" },
                   params.fetch("user"))
    end

    test "redacts credentials" do
      params = call(post("/entrar", user: { email: "a@b.com", password: "hunter2" }))

      assert_equal "a@b.com", params.dig("user", "email")
      assert_equal "[FILTERED]", params.dig("user", "password")
    end

    test "drops routing keys and the CSRF token" do
      params = call(post("/carrinho/items", product_id: "7", authenticity_token: "abc"))

      assert_equal({ "product_id" => "7" }, params)
    end

    test "keeps path params on a write so the record is identifiable" do
      params = call(post("/minha-conta/pedidos/PG-30443/cancelar", number: "PG-30443"))

      assert_equal({ "number" => "PG-30443" }, params)
    end

    test "logs only the query string on a read" do
      params = call(get("/checkout/retorno", order_nsu: "PG-67647"))

      assert_equal({ "order_nsu" => "PG-67647" }, params)
    end

    test "returns nil when there is nothing submitted" do
      assert_nil call(get("/carrinho"))
      assert_nil call(post("/carrinho/frete"))
    end

    test "clamps a runaway value instead of writing an unbounded log line" do
      params = call(post("/admin/produtos", description: "x" * 900))

      assert_equal "#{'x' * RequestParams::VALUE_LIMIT}…(900)", params.fetch("description")
    end

    test "describes an upload rather than serializing its bytes" do
      tempfile = Tempfile.new("label")
      tempfile.write("x" * 2048)
      tempfile.rewind
      upload = ActionDispatch::Http::UploadedFile.new(
        filename: "label.pdf", type: "application/pdf", tempfile: tempfile
      )
      params = call(post("/admin/produtos", photo: upload))

      assert_equal "#<upload label.pdf 2048b>", params.fetch("photo")
    end

    test "renders non-primitive values as strings" do
      params = call(post("/admin/produtos", published_at: Date.new(2026, 8, 10)))

      assert_equal "2026-08-10", params.fetch("published_at")
    end

    test "keeps the primitives a JSON body decodes to" do
      params = call(post("/carrinho/frete", quantity: 3, gift: true, wrap: false, note: nil))

      assert_equal({ "quantity" => 3, "gift" => true, "wrap" => false, "note" => nil }, params)
    end

    test "walks arrays" do
      params = call(post("/carrinho/items", option_ids: [ "3", "4" ]))

      assert_equal [ "3", "4" ], params.fetch("option_ids")
    end

    test "never lets a broken body take the request down with it" do
      request = Object.new
      def request.get? = raise(IOError, "truncated body")

      assert_equal RequestParams::UNREADABLE, RequestParams.call(request)
    end

    private

    def call(request)
      RequestParams.call(request)
    end

    def post(path, **params)
      ActionDispatch::TestRequest.create(
        "REQUEST_METHOD" => "POST", "PATH_INFO" => path
      ).tap { |request| request.request_parameters = params.deep_stringify_keys }
    end

    def get(path, **params)
      ActionDispatch::TestRequest.create(
        "REQUEST_METHOD" => "GET", "PATH_INFO" => path,
        "QUERY_STRING" => params.to_query
      )
    end
  end
end
