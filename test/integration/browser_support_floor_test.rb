require "test_helper"

class BrowserSupportFloorTest < ActionDispatch::IntegrationTest
  test "iOS 14 Safari in Instagram's in-app browser is served, not blocked" do
    get root_path, headers: { "HTTP_USER_AGENT" =>
      "Mozilla/5.0 (iPhone; CPU iPhone OS 14_8 like Mac OS X) AppleWebKit/605.1.15 " \
      "(KHTML, like Gecko) Mobile/15E148 Instagram 200.0.0.0.0 (iPhone12,1; iOS 14_8; pt_BR)" }
    assert_response :success
  end

  test "iOS 16 Safari is served" do
    get root_path, headers: { "HTTP_USER_AGENT" =>
      "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 " \
      "(KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1" }
    assert_response :success
  end

  test "browsers below the floor get 406 Not Acceptable" do
    get root_path, headers: { "HTTP_USER_AGENT" =>
      "Mozilla/5.0 (iPhone; CPU iPhone OS 12_5 like Mac OS X) AppleWebKit/605.1.15 " \
      "(KHTML, like Gecko) Version/12.1.2 Mobile/15E148 Safari/604.1" }
    assert_response :not_acceptable
  end

  test "Internet Explorer gets 406 Not Acceptable" do
    get root_path, headers: { "HTTP_USER_AGENT" =>
      "Mozilla/5.0 (Windows NT 10.0; WOW64; Trident/7.0; rv:11.0) like Gecko" }
    assert_response :not_acceptable
  end
end
