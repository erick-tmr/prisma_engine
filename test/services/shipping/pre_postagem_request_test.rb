require "test_helper"

module Shipping
  class PrePostagemRequestTest < ActiveSupport::TestCase
    test "builds the request from the order snapshot, user contact and line items" do
      request = Shipping::PrePostagemRequest.from_order(orders(:awaiting))

      assert_equal :pac, request.service
      assert_equal "PG-202606140001", request.observacao

      recipient = request.recipient
      assert_equal "Cliente Confirmado", recipient[:nome]
      assert_equal "11", recipient[:dddCelular]
      assert_equal "999998888", recipient[:celular]
      assert_equal "confirmed@example.com", recipient[:email]
      assert_equal "52998224725", recipient[:cpfCnpj]
      assert_equal "01310100", recipient.dig(:endereco, :cep)
      assert_equal "Apto 12", recipient.dig(:endereco, :complemento)

      item = request.items.sole
      assert_equal "Cartucho Game Boy — The Legend of Zelda: Link's Awakening DX", item[:conteudo]
      assert_equal "1", item[:quantidade]
      assert_equal "320.00", item[:valor]

      dimensions = request.dimensions
      assert_equal "120", dimensions[:pesoInformado]
      assert_equal "4", dimensions[:alturaInformada]
      assert_equal "16", dimensions[:larguraInformada]
      assert_equal "24", dimensions[:comprimentoInformado]
    end

    test "omits a blank complemento from the recipient address" do
      request = Shipping::PrePostagemRequest.from_order(orders(:confirmed_paid))

      assert_not request.recipient[:endereco].key?(:complemento)
    end
  end
end
