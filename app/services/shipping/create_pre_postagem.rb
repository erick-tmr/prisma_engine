module Shipping
  class CreatePrePostagem
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

    OBJECT_FORMAT_PACKAGE = "2".freeze

    def self.call(request, shipment:)
      new(request, shipment: shipment).call
    end

    def initialize(request, shipment:)
      @request = request
      @shipment = shipment
    end

    def call
      response = Correios::Api::PrePostagem.create(request_body)
      Shipping::ShipmentFactory.update_from_pre_postagem(shipment, response)
      validate_pre_postagem!
      shipment
    end

    private

    attr_reader :request, :shipment

    # A pré-postagem missing either field is unusable: every later step keys off
    # tracking_code, RequestLabel keys off pre_post_id, and nothing can backfill
    # either. Persist the payload first so the raw response survives for manual
    # review, then fail non-retryably rather than advancing the saga onto an
    # object we can neither track nor turn into a rótulo.
    def validate_pre_postagem!
      missing = %w[codigoObjeto id].zip([ shipment.tracking_code, shipment.pre_post_id ])
                                   .filter_map { |field, value| field if value.blank? }
      return if missing.empty?

      raise Correios::Api::InvalidObjectError,
            "pré-postagem #{shipment.pre_post_id.inspect} came back without #{missing.join(' and ')}"
    end

    def request_body
      {
        remetente: SENDER,
        destinatario: request.recipient,
        codigoServico: Shipping::SERVICES.fetch(request.service),
        numeroCartaoPostagem: Shipping::POSTAGE_CARD_NUMBER,
        codigoFormatoObjetoInformado: OBJECT_FORMAT_PACKAGE,
        itensDeclaracaoConteudo: request.items,
        cienteObjetoNaoProibido: "1",
        solicitarColeta: "N",
        observacao: request.observacao,
        logisticaReversa: "N",
        emiteDCe: "S"
      }.merge(request.dimensions)
    end
  end
end
