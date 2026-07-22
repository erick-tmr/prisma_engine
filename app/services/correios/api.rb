module Correios
  module Api
    BASE_URL = "https://api.correios.com.br".freeze

    def self.api_token
      Rails.application.credentials.dig(:correios, :api_token)
    end

    def self.cartao_api_token
      Rails.application.credentials.dig(:correios, :cartao_api_token)
    end

    Error = Class.new(StandardError)
    TransientError = Class.new(Error)
    InvalidObjectError = Class.new(Error)
    LabelGenerationFailedError = Class.new(Error)
  end
end
