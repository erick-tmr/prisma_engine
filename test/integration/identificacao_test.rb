require "test_helper"

class IdentificacaoTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "GET /identificacao requires login" do
    get identificacao_path
    assert_redirected_to new_user_session_path
  end

  test "GET /identificacao renders the placeholder for signed-in users" do
    sign_in users(:confirmed)
    get identificacao_path
    assert_response :success
    assert_match(/Identificação concluída/, response.body)
  end
end
