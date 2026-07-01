require "test_helper"

class HeroBannerTest < ActiveSupport::TestCase
  def build_banner(**attrs)
    banner = HeroBanner.new(**attrs)
    banner.image.attach(
      io: File.open(file_fixture("sample_product.jpg")),
      filename: "hero.jpg",
      content_type: "image/jpeg"
    )
    banner
  end

  test "an image is required" do
    banner = HeroBanner.new
    assert_not banner.valid?
    assert_includes banner.errors[:image], "não pode ficar em branco"
  end

  test "with an image attached the record is valid" do
    assert build_banner.valid?
  end

  test "rejects a negative position" do
    assert_not build_banner(position: -1).valid?
  end

  test "active scope returns only active banners" do
    visible = build_banner(active: true)
    hidden  = build_banner(active: false)
    visible.save!
    hidden.save!

    assert_includes HeroBanner.active, visible
    assert_not_includes HeroBanner.active, hidden
  end

  test "in_display_order sorts by position then id" do
    build_banner(position: 1).save!
    build_banner(position: 0).save!

    assert_equal [ 0, 1 ], HeroBanner.in_display_order.pluck(:position)
  end
end
