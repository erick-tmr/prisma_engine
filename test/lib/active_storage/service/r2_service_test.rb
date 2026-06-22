require "test_helper"
require "active_storage/service/r2_service"

class ActiveStorage::Service::R2ServiceTest < ActiveSupport::TestCase
  def build_service(public_host: "https://cdn.example.test")
    ActiveStorage::Service::R2Service.new(
      public_host: public_host,
      bucket: "test-bucket",
      endpoint: "https://acct.r2.cloudflarestorage.com",
      region: "auto",
      access_key_id: "key",
      secret_access_key: "secret",
      public: true
    )
  end

  test "is a public service" do
    assert build_service.public?
  end

  test "builds public URLs on the custom host" do
    assert_equal "https://cdn.example.test/abc123", build_service.url("abc123")
  end

  test "preserves slashes in variant keys instead of escaping them" do
    assert_equal "https://cdn.example.test/variants/abc/def", build_service.url("variants/abc/def")
  end

  test "drops the public-read ACL that R2 does not honor" do
    upload_options = build_service.instance_variable_get(:@upload_options)
    assert_not upload_options.key?(:acl)
  end
end
