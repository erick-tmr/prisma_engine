require "test_helper"
require "aws-sdk-s3"

module Emails
  class AssetUploaderTest < ActiveSupport::TestCase
    test "uploads every brand image under the emails/ prefix to the given bucket" do
      client = Aws::S3::Client.new(stub_responses: true)

      keys = File.stub(:binread, "png-bytes") do
        AssetUploader.new(client: client, bucket: "prisma-games-test").call
      end

      assert_equal %w[
        emails/dragon-fly.png
        emails/dragon-face.png
        emails/dragon-letter-full.png
        emails/prisma-games-logo.png
      ], keys

      requests = client.api_requests
      assert_equal keys, requests.map { |req| req[:params][:key] }
      assert(requests.all? { |req| req[:params][:bucket] == "prisma-games-test" })
      assert(requests.all? { |req| req[:params][:content_type] == "image/png" })
      assert(requests.all? { |req| req[:params][:body] == "png-bytes" })
    end

    test "r2_client builds an S3 client pointed at the given R2 endpoint" do
      client = AssetUploader.r2_client(
        access_key_id: "ak",
        secret_access_key: "sk",
        endpoint: "https://acct.r2.cloudflarestorage.com"
      )

      assert_kind_of Aws::S3::Client, client
      assert_equal "https://acct.r2.cloudflarestorage.com", client.config.endpoint.to_s
    end
  end
end
