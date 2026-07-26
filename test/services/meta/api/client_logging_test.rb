require "test_helper"

module Meta
  module Api
    class ClientLoggingTest < ActiveSupport::TestCase
      CATALOG_ID = "cat-1".freeze
      ITEMS_URL = "#{Meta::Api::BASE_URL}/#{Meta::Api::API_VERSION}/#{CATALOG_ID}/items_batch".freeze
      SETS_RE = Regexp.new(Regexp.escape("#{Meta::Api::BASE_URL}/#{Meta::Api::API_VERSION}/#{CATALOG_ID}/product_sets")).freeze

      setup do
        @sink = StringIO.new
        @previous_logger = Rails.logger
        Rails.logger = ActiveSupport::Logger.new(@sink)
      end

      teardown do
        Rails.logger = @previous_logger
      end

      def with_credentials(&block)
        Meta::Api.stub(:access_token, "super-secret-token") do
          Meta::Api.stub(:catalog_id, CATALOG_ID, &block)
        end
      end

      test "traces the request and response to the main log and redacts the Bearer token" do
        stub_request(:post, ITEMS_URL).to_return(
          status: 200, body: { "handles" => [ "h1" ] }.to_json, headers: { "Content-Type" => "application/json" }
        )

        with_credentials { Meta::Api::Catalog.batch([ { method: "UPDATE", data: { id: "1" } } ]) }

        log = @sink.string
        assert_match "request: POST", log
        assert_match "response: Status 200", log
        assert_match "Bearer [REDACTED]", log
        refute_match(/super-secret-token/, log)
      end

      test "redacts an access_token echoed inside a response body" do
        body = { "data" => [], "paging" => { "next" => "https://graph.facebook.com/x?access_token=EAAleaked123&after=1" } }.to_json
        stub_request(:get, SETS_RE).to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

        with_credentials { Meta::Api::ProductSets.list }

        log = @sink.string
        assert_match "access_token=[REDACTED]", log
        refute_match(/EAAleaked123/, log)
      end
    end
  end
end
