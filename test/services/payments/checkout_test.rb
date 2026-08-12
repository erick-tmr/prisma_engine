require "test_helper"

module Payments
  class CheckoutTest < ActiveSupport::TestCase
    LINKS_URL = "#{InfinitePay::Api::BASE_URL}/links".freeze

    setup do
      @order = Order.create!(user: users(:confirmed), subtotal_cents: 18_000, total_cents: 19_984)
      @order.create_shipment!(
        service: "sedex", shipping_cents: 1_984, weight_grams: 120, height_cm: 4, width_cm: 16, length_cm: 24,
        receiver_name: "Cliente Confirmado", receiver_cpf: "52998224725",
        zip: "01310100", street: "Av. Paulista", number: "1578",
        complement: "11º andar", neighborhood: "Bela Vista", city: "São Paulo", state: "SP"
      )
      @order.order_items.create!(name: "Cartucho Zelda", unit_price_cents: 18_000, quantity: 1, chosen_options: [ "ROM: Zelda" ])
    end

    def stub_links
      stub_request(:post, LINKS_URL).to_return(
        status: 200,
        body: { "url" => "https://checkout.infinitepay.io/prisma_games?lenc=xyz" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    end

    def start
      Payments::Checkout.start(@order, redirect_url: "https://shop.test/checkout/retorno", webhook_url: "https://shop.test/pagamentos/webhook")
    end

    test "builds the InfinitePay payload from the order and returns the checkout url" do
      stub_links
      assert_equal "https://checkout.infinitepay.io/prisma_games?lenc=xyz", start

      assert_requested(:post, LINKS_URL) do |req|
        body = JSON.parse(req.body)
        assert_equal "prisma_games", body["handle"]
        assert_equal @order.number, body["order_nsu"]
        assert_equal "https://shop.test/checkout/retorno", body["redirect_url"]
        assert_equal "https://shop.test/pagamentos/webhook", body["webhook_url"]

        assert_equal 2, body["items"].size
        assert_equal({ "description" => "Cartucho Zelda", "quantity" => 1, "price" => 18_000 }, body["items"][0])
        assert_equal "Frete: sedex", body["items"][1]["description"]
        assert_equal 1_984, body["items"][1]["price"]

        assert_equal "Cliente Confirmado", body["customer"]["name"]
        assert_equal "confirmed@example.com", body["customer"]["email"]
        assert_equal "+5511999998888", body["customer"]["phone_number"]

        assert_equal "01310100", body["address"]["cep"]
        assert_equal "Av. Paulista", body["address"]["street"]
        assert_equal "Bela Vista", body["address"]["neighborhood"]
        assert_equal "1578", body["address"]["number"]
        assert_equal "11º andar", body["address"]["complement"]
        true
      end
    end

    test "keeps a phone that already carries the +55 country code" do
      @order.user.update!(phone: "+55 (11) 93245-8443")
      stub_links
      start
      assert_requested(:post, LINKS_URL) do |req|
        assert_equal "+5511932458443", JSON.parse(req.body)["customer"]["phone_number"]
        true
      end
    end

    test "omits phone_number entirely when the user has no phone" do
      @order.user.update_columns(phone: "")
      stub_links
      start
      assert_requested(:post, LINKS_URL) do |req|
        customer = JSON.parse(req.body)["customer"]
        assert_not customer.key?("phone_number")
        assert_equal "Cliente Confirmado", customer["name"]
        true
      end
    end

    test "omits the frete line when a merge carrier charges nothing extra for shipping" do
      @order.shipment.update!(shipping_cents: 0)
      @order.update!(total_cents: 18_000)
      stub_links

      start

      assert_requested(:post, LINKS_URL) do |req|
        items = JSON.parse(req.body)["items"]
        assert_equal [ "Cartucho Zelda" ], items.map { |item| item["description"] }
        assert_equal 18_000, items.sum { |item| item["price"] * item["quantity"] }
        true
      end
    end

    test "logs the rejection with the order number and the vendor message, then re-raises" do
      stub_request(:post, LINKS_URL).to_return(status: 422, body: { "message" => "invalid item price" }.to_json)

      log = with_log_sink { assert_raises(InfinitePay::Api::Error) { start } }

      assert_match "[Payments::Checkout]", log
      assert_match "order=#{@order.number}", log
      assert_match "infinitepay returned 422", log
      assert_match "invalid item price", log
    end

    private

    def with_log_sink
      sink = StringIO.new
      previous_logger = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(sink)
      yield
      sink.string
    ensure
      Rails.logger = previous_logger
    end
  end
end
