module Shipping
  SERVICES = {
    sedex:       "03220",
    pac:         "03298",
    mini_envios: "04227"
  }.freeze

  PACKAGE_DIMENSIONS = {
    altura_cm:      4,
    largura_cm:     16,
    comprimento_cm: 24
  }.freeze

  ORIGIN_CEP = "37600000".freeze

  POSTAGE_CARD_NUMBER = "0076738043".freeze

  PACKAGE_OVERHEAD_GRAMS = 52

  PREPOSTAGEM_INITIAL_DELAY = 10.seconds
  PREPOSTAGEM_POLL_INTERVAL = 10.seconds
  PREPOSTAGEM_MAX_POLL_ATTEMPTS = 18

  PrePostagemPending = Class.new(StandardError)
end
