require "aws-sdk-s3"

module Emails
  class AssetUploader
    ENDPOINT = "https://ebd6066b8c5c56f2942edd6b4267b706.r2.cloudflarestorage.com".freeze

    ASSETS = {
      "dragon-fly.png" => "public/images/emails/dragon-fly.png",
      "dragon-face.png" => "public/images/emails/dragon-face.png",
      "dragon-letter-full.png" => "public/images/emails/dragon-letter-full.png",
      "prisma-games-logo.png" => "public/images/prisma-games-logo.png"
    }.freeze

    def self.r2_client(access_key_id:, secret_access_key:)
      Aws::S3::Client.new(
        access_key_id: access_key_id,
        secret_access_key: secret_access_key,
        endpoint: ENDPOINT,
        region: "auto",
        force_path_style: true
      )
    end

    def initialize(client:, bucket:)
      @client = client
      @bucket = bucket
    end

    def call
      ASSETS.map do |name, path|
        key = "emails/#{name}"
        @client.put_object(
          bucket: @bucket,
          key: key,
          body: File.binread(Rails.root.join(path)),
          content_type: "image/png",
          cache_control: "public, max-age=31536000, immutable"
        )
        key
      end
    end
  end
end
