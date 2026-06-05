module Correios
  module Api
    # Correios timestamps carry no UTC offset and are always Brasília time
    # (America/Sao_Paulo, -03:00, no DST since 2019). Parse them in that zone so
    # ActiveRecord stores the correct UTC instant. Strings that do carry an offset
    # are still honoured.
    module Timestamp
      ZONE = ActiveSupport::TimeZone["America/Sao_Paulo"]

      def self.parse(value)
        return if value.blank?

        ZONE.parse(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
