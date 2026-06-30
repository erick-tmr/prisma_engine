module LinkPreview
  module Api
    USER_AGENT = "PrismaGamesBot/1.0 (+https://prismagames.com.br)".freeze

    Error = Class.new(StandardError)
    TransientError = Class.new(Error)
  end
end
