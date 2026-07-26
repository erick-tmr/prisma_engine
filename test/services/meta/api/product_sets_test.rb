require "test_helper"

module Meta
  module Api
    class ProductSetsTest < ActiveSupport::TestCase
      CATALOG_ID = "cat-123".freeze
      SETS_URL = "#{Meta::Api::BASE_URL}/#{Meta::Api::API_VERSION}/#{CATALOG_ID}/product_sets".freeze
      NODE_URL = "#{Meta::Api::BASE_URL}/#{Meta::Api::API_VERSION}/set-9".freeze
      SETS_RE = Regexp.new(Regexp.escape(SETS_URL)).freeze
      NODE_RE = Regexp.new(Regexp.escape(NODE_URL)).freeze

      def with_credentials(&block)
        Meta::Api.stub(:access_token, "test-token") do
          Meta::Api.stub(:catalog_id, CATALOG_ID, &block)
        end
      end

      test "list returns the data array of sets" do
        stub_request(:get, SETS_RE).to_return(
          status: 200, body: { "data" => [ { "id" => "1", "name" => "Game Boy" } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

        sets = with_credentials { Meta::Api::ProductSets.list }

        assert_equal "Game Boy", sets.first["name"]
        assert_requested(:get, SETS_RE) { |req| Rack::Utils.parse_query(req.uri.query)["fields"] == "name" }
      end

      test "create POSTs name, filter and publish_to_shops, and returns the body" do
        stub_request(:post, SETS_RE).to_return(
          status: 200, body: { "id" => "set-9" }.to_json, headers: { "Content-Type" => "application/json" }
        )

        body = with_credentials do
          Meta::Api::ProductSets.create(
            name: "Game Boy", filter: { "product_type" => { "eq" => "Game Boy Classic" } }, shop_id: "shop-1"
          )
        end

        assert_equal "set-9", body["id"]
        assert_requested(:post, SETS_RE) do |req|
          params = Rack::Utils.parse_query(req.uri.query)
          assert_equal "Game Boy", params["name"]
          assert_equal({ "product_type" => { "eq" => "Game Boy Classic" } }, JSON.parse(params["filter"]))
          assert_equal [ { "shop_id" => "shop-1" } ], JSON.parse(params["publish_to_shops"])
          assert_equal "Bearer test-token", req.headers["Authorization"]
          true
        end
      end

      test "update POSTs the filter to the set node" do
        stub_request(:post, NODE_RE).to_return(
          status: 200, body: { "success" => true }.to_json, headers: { "Content-Type" => "application/json" }
        )

        with_credentials { Meta::Api::ProductSets.update("set-9", filter: { "retailer_id" => { "is_any" => [ "8" ] } }) }

        assert_requested(:post, NODE_RE) do |req|
          params = Rack::Utils.parse_query(req.uri.query)
          assert_equal({ "retailer_id" => { "is_any" => [ "8" ] } }, JSON.parse(params["filter"]))
          true
        end
      end

      test "raises PermanentError on a 4xx" do
        stub_request(:post, SETS_RE).to_return(status: 400, body: { "error" => { "code" => 100 } }.to_json)
        assert_raises(Meta::Api::PermanentError) do
          with_credentials { Meta::Api::ProductSets.create(name: "x", filter: {}, shop_id: "s") }
        end
      end

      test "raises PermanentError on a 4xx whose body is not JSON" do
        stub_request(:post, SETS_RE).to_return(status: 400, body: "<html>bad</html>")
        assert_raises(Meta::Api::PermanentError) do
          with_credentials { Meta::Api::ProductSets.create(name: "x", filter: {}, shop_id: "s") }
        end
      end

      test "raises EmptyProductSetError when Meta rejects an empty set" do
        stub_request(:post, SETS_RE).to_return(
          status: 400, body: { "error" => { "code" => 100, "error_subcode" => 1_798_130 } }.to_json
        )
        assert_raises(Meta::Api::EmptyProductSetError) do
          with_credentials { Meta::Api::ProductSets.create(name: "x", filter: {}, shop_id: "s") }
        end
      end

      test "raises TransientError on a 5xx" do
        stub_request(:get, SETS_RE).to_return(status: 503, body: "down")
        assert_raises(Meta::Api::TransientError) { with_credentials { Meta::Api::ProductSets.list } }
      end

      test "raises TransientError on a timeout" do
        stub_request(:post, SETS_RE).to_timeout
        assert_raises(Meta::Api::TransientError) do
          with_credentials { Meta::Api::ProductSets.create(name: "x", filter: {}, shop_id: "s") }
        end
      end

      test "raises PermanentError on an unparseable body" do
        stub_request(:get, SETS_RE).to_return(status: 200, body: "not json")
        assert_raises(Meta::Api::PermanentError) { with_credentials { Meta::Api::ProductSets.list } }
      end
    end
  end
end
