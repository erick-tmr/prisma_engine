module Shipping
  # Parameter object for the variable inputs of a pré-postagem, so
  # Shipping::CreatePrePostagem takes one argument instead of a long keyword list.
  # Only `service` is really chosen today; the rest are hardcoded placeholders until
  # the Order / customer / cart models feed them (see docs/architecture.md). Use
  # `.placeholder(service:)` for the current case and `#with` to override a field.
  PrePostagemRequest = Data.define(:service, :recipient, :items, :dimensions, :observacao) do
    # The buyer. Placeholder until customer profiles exist.
    PLACEHOLDER_RECIPIENT = {
      nome: "Erick Takeshi Mine Rezende",
      dddCelular: "11",
      celular: "973498347",
      email: "ericktm93@gmail.com",
      cpfCnpj: "40706252837",
      endereco: {
        cep: "03131010",
        logradouro: "Rua Orfanato",
        numero: "593",
        complemento: "Apto 113 B",
        bairro: "Vila Prudente",
        cidade: "Sao Paulo",
        uf: "SP"
      }
    }.freeze

    # The package contents declaration. Placeholder until order line-items exist.
    PLACEHOLDER_ITEMS = [
      { conteudo: "Jogo de Gameboy", quantidade: "1", valor: "200.00" }
    ].freeze

    # Placeholder until a packing algorithm exists.
    PLACEHOLDER_DIMENSIONS = {
      pesoInformado: "120",        # grams
      alturaInformada: "4",        # cm
      larguraInformada: "16",      # cm
      comprimentoInformado: "24"   # cm
    }.freeze

    # Placeholder until the order identifier exists.
    PLACEHOLDER_OBSERVACAO = "Pedido #123".freeze

    # The current hardcoded request — only the service is chosen.
    def self.placeholder(service:)
      new(
        service: service,
        recipient: PLACEHOLDER_RECIPIENT,
        items: PLACEHOLDER_ITEMS,
        dimensions: PLACEHOLDER_DIMENSIONS,
        observacao: PLACEHOLDER_OBSERVACAO
      )
    end
  end
end
