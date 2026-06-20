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
end
