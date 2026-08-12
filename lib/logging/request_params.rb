require "active_support/parameter_filter"

module Logging
  module RequestParams
    ROUTING_KEYS = %w[controller action format _method authenticity_token].freeze
    CREDENTIALS = %i[passw secret token _key crypt salt certificate otp cvv cvc].freeze
    VALUE_LIMIT = 512
    UNREADABLE = "[UNREADABLE]".freeze

    FILTER = ActiveSupport::ParameterFilter.new(CREDENTIALS)

    module_function

    def call(request)
      scrub(FILTER.filter(submitted(request))).presence
    rescue StandardError
      UNREADABLE
    end

    def submitted(request)
      return request.query_parameters if request.get? || request.head?

      request.params.except(*ROUTING_KEYS)
    end

    def scrub(value)
      case value
      when Hash then value.transform_values { |nested| scrub(nested) }
      when Array then value.map { |nested| scrub(nested) }
      when String then clamp(value)
      when Numeric, TrueClass, FalseClass, NilClass then value
      when ActionDispatch::Http::UploadedFile then summarize(value)
      else clamp(value.to_s)
      end
    end

    def summarize(upload)
      "#<upload #{upload.original_filename} #{upload.size}b>"
    end

    def clamp(string)
      return string if string.length <= VALUE_LIMIT

      "#{string[0, VALUE_LIMIT]}…(#{string.length})"
    end
  end
end
