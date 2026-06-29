require "test_helper"

module Correios
  module Api
    class ClientLoggingTest < ActiveSupport::TestCase
      BASE = Correios::Api::BASE_URL
      CODE = "AD483393343BR".freeze

      setup do
        @sink = StringIO.new
        @prev_logger = Correios::Api::Client.instance_variable_get(:@request_logger)
        Correios::Api::Client.instance_variable_set(:@request_logger, ActiveSupport::Logger.new(@sink))

        stub_request(:get, "#{BASE}/srorastro/v1/objetos/#{CODE}?resultado=T")
          .to_return(
            status: 200,
            body: { "objetos" => [ { "codObjeto" => CODE, "mensagem" => "SRO-020" } ] }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      teardown do
        Correios::Api::Client.instance_variable_set(:@request_logger, @prev_logger)
      end

      test "traces the request line and the response status and body" do
        Correios::Api::Tracking.fetch(CODE)

        log = @sink.string
        assert_match %r{request: GET #{Regexp.escape("#{BASE}/srorastro/v1/objetos/#{CODE}")}}, log
        assert_match "response: Status 200", log
        assert_match "SRO-020", log
      end

      test "redacts the Bearer token so the credential never reaches the log" do
        Correios::Api.stub(:api_token, "super-secret-token") do
          Correios::Api::Tracking.fetch(CODE)
        end

        assert_match "Bearer [REDACTED]", @sink.string
        refute_match(/super-secret-token/, @sink.string)
      end
    end
  end
end
