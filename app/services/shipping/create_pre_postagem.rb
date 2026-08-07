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
      ensure_object_code!
      shipment
    end

    private

    attr_reader :request, :shipment

    # A pré-postagem that comes back without a codigoObjeto is unusable: every
    # later step keys off tracking_code, and nothing can backfill it. Persist the
    # payload first so the pre_post_id survives for manual review, then fail
    # non-retryably rather than advancing the saga onto an object we cannot track.
    def ensure_object_code!
      return if shipment.tracking_code.present?

      raise Correios::Api::InvalidObjectError,
            "pré-postagem #{shipment.pre_post_id.inspect} returned no codigoObjeto"
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
