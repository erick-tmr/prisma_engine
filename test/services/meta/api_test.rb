require "test_helper"

module Meta
  class ApiTest < ActiveSupport::TestCase
    test "exposes catalog credentials without raising when they are unset" do
      assert_nothing_raised do
        Meta::Api.access_token
        Meta::Api.catalog_id
        Meta::Api.shop_id
      end
    end

    test "shops_configured? also requires a shop id" do
      assert_not Meta::Api.shops_configured?

      Meta::Api.stub(:access_token, "token") do
        Meta::Api.stub(:catalog_id, "916320183192222") do
          assert_not Meta::Api.shops_configured?

          Meta::Api.stub(:shop_id, "shop-1") do
            assert Meta::Api.shops_configured?
          end
        end
      end
    end

    test "configured? requires both an access token and a catalog id" do
      assert_not Meta::Api.configured?

      Meta::Api.stub(:access_token, "token") do
        assert_not Meta::Api.configured?

        Meta::Api.stub(:catalog_id, "916320183192222") do
          assert Meta::Api.configured?
        end
      end
    end
  end
end
