module Shipping
  SERVICES = {
    sedex:       "03220",
    pac:         "03298",
    mini_envios: "04227"
  }.freeze

  SERVICE_LABELS = {
    sedex:       "SEDEX",
    pac:         "PAC",
    mini_envios: "Mini Envios"
  }.freeze

  def self.service_label(service)
    SERVICE_LABELS.fetch(service.to_s.to_sym, service.to_s.upcase)
  end

  PACKAGE_DIMENSIONS = {
    altura_cm:      4,
    largura_cm:     16,
    comprimento_cm: 24
  }.freeze

  ORIGIN_CEP = "37600000".freeze

  POSTAGE_CARD_NUMBER = "0076738043".freeze

  PACKAGE_OVERHEAD_GRAMS = 52

  PREPOSTAGEM_INITIAL_DELAY = 10.seconds
  PREPOSTAGEM_POLL_BASE_DELAY = 10.seconds
  PREPOSTAGEM_POLL_MAX_DELAY = 2.minutes
  PREPOSTAGEM_MAX_POLL_ATTEMPTS = 18

  PrePostagemPending = Class.new(StandardError)
end
