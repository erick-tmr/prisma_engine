require "test_helper"

class StorefrontImageHelperTest < ActionView::TestCase
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

  test "a preset renders a responsive srcset, sizes and a transformed fallback src" do
    html = storefront_image_tag("#{HOST}/k", preset: :card, alt: "Boxart", width: 600, height: 400, loading: "lazy")

    assert_includes html, %(alt="Boxart")
    assert_includes html, %(width="600")
    assert_includes html, %(loading="lazy")
    assert_includes html, %(sizes="(min-width: 768px) 320px, 50vw")
    assert_includes html, "cdn-cgi/image/width=320"
    assert_includes html, "320w"
    assert_includes html, %(src="#{HOST}/cdn-cgi/image/width=640,)
  end

  test "resize renders a single transformed src with no srcset" do
    html = storefront_image_tag("#{HOST}/k", resize: 240, alt: "Thumb")

    assert_includes html, %(src="#{HOST}/cdn-cgi/image/width=240,)
    assert_not_includes html, "srcset"
  end

  test "renders a plain img when transforms are disabled" do
    Rails.application.config.x.cdn_image_transforms = nil
    html = storefront_image_tag("#{HOST}/k", preset: :card, alt: "Boxart", loading: "lazy")

    assert_includes html, %(src="#{HOST}/k")
    assert_not_includes html, "srcset"
    assert_not_includes html, "cdn-cgi"
    assert_includes html, %(loading="lazy")
  end

  test "renders a plain img when neither preset nor resize is given" do
    html = storefront_image_tag("#{HOST}/k", alt: "Plain")

    assert_includes html, %(src="#{HOST}/k")
    assert_not_includes html, "srcset"
    assert_not_includes html, "cdn-cgi"
  end

  test "hero_preload_link builds a preload link matching the hero preset" do
    html = hero_preload_link("#{HOST}/hero")

    assert_includes html, %(rel="preload")
    assert_includes html, %(as="image")
    assert_includes html, %(fetchpriority="high")
    assert_includes html, %(imagesizes="(max-width: 1320px) 100vw, 1288px")
    assert_includes html, "cdn-cgi/image/width=1920"
  end

  test "hero_preload_link is blank when transforms are disabled" do
    Rails.application.config.x.cdn_image_transforms = nil
    assert_equal "", hero_preload_link("#{HOST}/hero")
  end
end
