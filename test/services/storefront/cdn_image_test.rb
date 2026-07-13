require "test_helper"

module Storefront
  class CdnImageTest < ActiveSupport::TestCase
    HOST = "https://cdn.example.test".freeze

    setup do
      @orig_flag = Rails.application.config.x.cdn_image_transforms
      @orig_host = Rails.application.config.x.r2_public_host
      Rails.application.config.x.cdn_image_transforms = true
      Rails.application.config.x.r2_public_host = HOST
    end

    teardown do
      Rails.application.config.x.cdn_image_transforms = @orig_flag
      Rails.application.config.x.r2_public_host = @orig_host
    end

    test "transform wraps a CDN URL with cdn-cgi options" do
      assert_equal "#{HOST}/cdn-cgi/image/width=640,quality=78,format=auto,fit=scale-down,metadata=none,onerror=redirect/key123",
                   CdnImage.transform("#{HOST}/key123", width: 640)
    end

    test "transform honours a custom quality" do
      assert_equal "#{HOST}/cdn-cgi/image/width=240,quality=50,format=auto,fit=scale-down,metadata=none,onerror=redirect/key123",
                   CdnImage.transform("#{HOST}/key123", width: 240, quality: 50)
    end

    test "transform tolerates a public host with a trailing slash" do
      Rails.application.config.x.r2_public_host = "#{HOST}/"
      assert_equal "#{HOST}/cdn-cgi/image/width=640,quality=78,format=auto,fit=scale-down,metadata=none,onerror=redirect/key123",
                   CdnImage.transform("#{HOST}/key123", width: 640)
    end

    test "srcset builds a descriptor for each width" do
      assert_equal(
        "#{HOST}/cdn-cgi/image/width=320,quality=78,format=auto,fit=scale-down,metadata=none,onerror=redirect/k 320w, " \
        "#{HOST}/cdn-cgi/image/width=640,quality=78,format=auto,fit=scale-down,metadata=none,onerror=redirect/k 640w",
        CdnImage.srcset("#{HOST}/k", widths: [ 320, 640 ])
      )
    end

    test "passes the URL through untouched when transforms are disabled" do
      Rails.application.config.x.cdn_image_transforms = nil
      assert_equal "#{HOST}/key123", CdnImage.transform("#{HOST}/key123", width: 640)
    end

    test "passes the URL through untouched when no public host is configured" do
      Rails.application.config.x.r2_public_host = nil
      assert_equal "#{HOST}/key123", CdnImage.transform("#{HOST}/key123", width: 640)
    end

    test "passes a URL that is not on the CDN host through untouched" do
      assert_equal "/images/test-cartridge.png", CdnImage.transform("/images/test-cartridge.png", width: 640)
    end

    test "passes an SVG on the CDN host through untouched" do
      assert_equal "#{HOST}/logo.svg", CdnImage.transform("#{HOST}/logo.svg", width: 640)
    end

    test "srcset passes each width through untouched when disabled" do
      Rails.application.config.x.cdn_image_transforms = nil
      assert_equal "#{HOST}/k 320w, #{HOST}/k 640w", CdnImage.srcset("#{HOST}/k", widths: [ 320, 640 ])
    end
  end
end
