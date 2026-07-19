require "test_helper"

module Meta
  class ApiTest < ActiveSupport::TestCase
    test "exposes catalog credentials without raising when they are unset" do
      assert_nothing_raised do
        Meta::Api.access_token
        Meta::Api.catalog_id
      end
    end
  end
end
