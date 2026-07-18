module CheckoutErrors
  ERROR_MESSAGES = {
    empty_cart:           "Seu carrinho está vazio.",
    invalid_address:      "Selecione um endereço de entrega válido.",
    shipping_unavailable: "A forma de envio escolhida não está disponível. Escolha outra.",
    shipping_error:       "Não foi possível calcular o frete agora. Tente novamente em instantes.",
    payment_error:        "Não foi possível iniciar o pagamento agora. Tente novamente em instantes.",
    no_mergeable:         "Você não tem outros pedidos disponíveis para juntar."
  }.freeze
end
