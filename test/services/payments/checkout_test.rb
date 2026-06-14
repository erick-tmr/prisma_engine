require "test_helper"

module Payments
  class CheckoutTest < ActiveSupport::TestCase
    LINKS_URL = "#{InfinitePay::Api::BASE_URL}/links".freeze

    setup do
      @prev_handle = ENV["INFINITEPAY_HANDLE"]
      ENV["INFINITEPAY_HANDLE"] = "prisma_games"
      @order = Order.create!(
        user: users(:confirmed),
        subtotal_cents: 18_000, shipping_cents: 1_984, total_cents: 19_984,
        shipping_service: "sedex",
        ship_receiver_name: "Cliente Confirmado", ship_receiver_cpf: "52998224725",
        ship_zip: "01310100", ship_street: "Av. Paulista", ship_number: "1578",
        ship_complement: "11º andar", ship_neighborhood: "Bela Vista",
        ship_city: "São Paulo", ship_state: "SP"
      )
      @order.order_items.create!(name: "Cartucho Zelda", unit_price_cents: 18_000, quantity: 1, chosen_options: [ "ROM: Zelda" ])
    end

    teardown { ENV["INFINITEPAY_HANDLE"] = @prev_handle }

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
        assert_equal "Frete — sedex", body["items"][1]["description"]
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
  end
end
