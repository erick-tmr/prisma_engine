require "test_helper"

module Payments
  class CheckoutTest < ActiveSupport::TestCase
    LINKS_URL = "#{InfinitePay::Api::BASE_URL}/links".freeze

    setup do
      @prev_handle = ENV["INFINITEPAY_HANDLE"]
      ENV["INFINITEPAY_HANDLE"] = "prisma_games"
      @order = Order.create!(user: users(:confirmed), subtotal_cents: 18_000, total_cents: 19_984)
      @order.create_shipment!(
        service: "sedex", shipping_cents: 1_984, weight_grams: 120, height_cm: 4, width_cm: 16, length_cm: 24,
        receiver_name: "Cliente Confirmado", receiver_cpf: "52998224725",
        zip: "01310100", street: "Av. Paulista", number: "1578",
        complement: "11º andar", neighborhood: "Bela Vista", city: "São Paulo", state: "SP"
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

        assert_equal 1, body["items"].size
        assert_equal({ "description" => "Cartucho Zelda", "quantity" => 1, "price" => 18_000 }, body["items"][0])

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
