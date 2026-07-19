module Meta
  module Api
    BASE_URL = "https://graph.facebook.com".freeze
    API_VERSION = "v21.0".freeze

    def self.access_token
      Rails.application.credentials.dig(:meta, :access_token)
    end

    def self.catalog_id
      Rails.application.credentials.dig(:meta, :catalog_id)
    end

    Error = Class.new(StandardError)
    TransientError = Class.new(Error)
    PermanentError = Class.new(Error)
  end
end
