require "resolv"
require "ipaddr"

module LinkPreview
  module Api
    module SafeUrl
      module_function

      BLOCKED = [
        IPAddr.new("0.0.0.0/8"),
        IPAddr.new("10.0.0.0/8"),
        IPAddr.new("127.0.0.0/8"),
        IPAddr.new("169.254.0.0/16"),
        IPAddr.new("172.16.0.0/12"),
        IPAddr.new("192.168.0.0/16"),
        IPAddr.new("::1/128"),
        IPAddr.new("fc00::/7"),
        IPAddr.new("fe80::/10")
      ].freeze

      def call(url)
        uri = URI.parse(url)
        raise Error, "unsupported URL: #{url}" unless uri.is_a?(URI::HTTP) && uri.host.present?

        guard_private_addresses(uri.host)
        url
      rescue URI::InvalidURIError
        raise Error, "invalid URL: #{url}"
      end

      def guard_private_addresses(host)
        addresses = Resolv.getaddresses(host)
        raise TransientError, "cannot resolve #{host}" if addresses.empty?
        raise Error, "blocked address for #{host}" if addresses.any? { |address| blocked?(address) }
      end

      def blocked?(address)
        ip = IPAddr.new(address)
        BLOCKED.any? { |range| range.include?(ip) }
      end
    end
  end
end
