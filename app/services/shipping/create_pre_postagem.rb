module Shipping
  # Use case: create a Correios pré-postagem and persist it as a Shipment.
  #
  #   request = Shipping::PrePostagemRequest.placeholder(service: :sedex)
  #   Shipping::CreatePrePostagem.call(request, order: order)
  #
  # Owns the fixed store config (sender, postage card, object format); the variable
  # inputs arrive in the PrePostagemRequest. Delegates the HTTP to
  # Correios::Api::PrePostagem and the persistence to Shipping::ShipmentFactory.
  class CreatePrePostagem
    # The store. Hardcoded until seller settings exist. The CEP lives in
    # `Shipping::ORIGIN_CEP` so the price/prazo quote can reuse it.
    SENDER = {
      nome: "Prisma Games",
      dddCelular: "35",
      celular: "920001100",
      email: "vininess@hotmail.com",
      cpfCnpj: "43773766000111",
      endereco: {
        cep:        Shipping::ORIGIN_CEP,
        logradouro: "Rua José Cláudio Venturelli",
        numero:     "156",
        bairro:     "Vila Mariana",
        cidade:     "Cambuí",
        uf:         "MG"
      }
    }.freeze

    POSTAGE_CARD_NUMBER = "0076738043".freeze # numeroCartaoPostagem — seller settings later
    OBJECT_FORMAT_PACKAGE = "2".freeze        # codigoFormatoObjetoInformado: 2 = pacote

    def self.call(request, order:)
      new(request, order: order).call
    end

    def initialize(request, order:)
      @request = request
      @order = order
    end

    # Returns the persisted Shipment.
    def call
      response = Correios::Api::PrePostagem.create(request_body)
      Shipping::ShipmentFactory.from_pre_postagem(response, order: order)
    end

    private

    attr_reader :request, :order

    def request_body
      {
        remetente: SENDER,
        destinatario: request.recipient,
        codigoServico: Shipping::SERVICES.fetch(request.service),
        numeroCartaoPostagem: POSTAGE_CARD_NUMBER,
        codigoFormatoObjetoInformado: OBJECT_FORMAT_PACKAGE,
        itensDeclaracaoConteudo: request.items,
        cienteObjetoNaoProibido: "1", # we never ship prohibited items
        solicitarColeta: "N",         # never ask Correios to collect at the store
        observacao: request.observacao,
        logisticaReversa: "N",        # returns are handled manually, not via Correios
        emiteDCe: "S"                 # always emit the electronic content declaration
      }.merge(request.dimensions)
    end
  end
end
