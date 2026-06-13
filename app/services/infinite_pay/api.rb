module InfinitePay
  module Api
    BASE_URL = "https://api.checkout.infinitepay.io".freeze

    Error = Class.new(StandardError)
    TransientError = Class.new(Error)
  end
end
