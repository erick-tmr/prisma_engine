module Correios
  module Api
    # Correios sends a field absent on one call, null on the next, and blank on a
    # third, for the same object. Reading with a bare fetch turns the first case
    # into a KeyError that escapes our error vocabulary, and reading with [] turns
    # all three into a nil that gets persisted and only fails much later, on some
    # other row, with no trace of the response that produced it.
    #
    # Every read of a Correios body goes through here instead: absent, null and
    # blank collapse to "", and the require_* readers reject at the point of
    # reading, in our own vocabulary, whatever the caller cannot work with.
    module Payload
      def self.hash(body)
        body.is_a?(Hash) ? body : {}
      end

      def self.string(body, key)
        hash(body).fetch(key, "").to_s.strip
      end

      def self.require_string(body, key, context)
        value = string(body, key)
        return value if value.present?

        raise Correios::Api::InvalidObjectError, "#{context}: #{key} came back empty"
      end

      def self.integer(body, key)
        Integer(string(body, key), exception: false)
      end

      def self.decimal(body, key)
        Float(string(body, key).tr(",", "."), exception: false)
      end

      def self.time(body, key)
        Correios::Api::Timestamp.parse(string(body, key))
      end
    end
  end
end
