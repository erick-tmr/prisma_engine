require "test_helper"

class RecommendationsNavTest < ActionDispatch::IntegrationTest
  test "home renders recommendations with favicon and letter-avatar fallbacks" do
    Recommendation.create!(
      url: "https://hasicon.example/", title: "ComIconeXYZ", tagline: "tem favicon", position: 0,
      favicon_data_uri: "data:image/svg+xml;base64,#{Base64.strict_encode64("<svg/>")}"
    )
    Recommendation.create!(
      url: "https://noicon.example/", title: "SemIconeXYZ", tagline: "sem favicon", position: 1
    )
    Recommendation.create!(
      url: "https://hidden.example/", title: "OcultaXYZ", active: false, position: 2
    )

    get root_path
    assert_response :success

    assert_select ".links-menu__section-title", /Recomendações do Vini/
    assert_select "img.partner-avatar--img"
    assert_select 'span.partner-avatar[style*="--avatar-gradient"]'
    assert_select "i.bi-box-arrow-up-right"
    assert_match "ComIconeXYZ", response.body
    assert_match "SemIconeXYZ", response.body
    assert_no_match(/OcultaXYZ/, response.body)
  end
end
