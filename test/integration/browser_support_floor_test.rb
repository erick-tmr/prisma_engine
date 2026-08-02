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

  test "Meta's composite crawler UA is served despite reporting Safari 9" do
    get root_path, headers: { "HTTP_USER_AGENT" =>
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_1) AppleWebKit/601.2.4 (KHTML, like Gecko) " \
      "Version/9.0.1 Safari/601.2.4 facebookexternalhit/1.1 Facebot Twitterbot/1.0" }
    assert_response :success
    assert_select "meta[property='og:title']", count: 1
  end

  test "the bare facebookexternalhit UA is served" do
    get root_path, headers: { "HTTP_USER_AGENT" =>
      "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)" }
    assert_response :success
  end

  test "an old browser that is not a crawler is still blocked" do
    get root_path, headers: { "HTTP_USER_AGENT" =>
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_1) AppleWebKit/601.2.4 (KHTML, like Gecko) " \
      "Version/9.0.1 Safari/601.2.4" }
    assert_response :not_acceptable
  end
end
