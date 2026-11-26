require "test_helper"

class StorefrontThemeTest < ActionDispatch::IntegrationTest
  test "the storefront uses its regular look outside the black friday window" do
    get root_path

    assert_response :success
    assert_select "link[href*=?]", "themes/black-friday", count: 0
  end

  test "the storefront loads the black friday stylesheet last while the window is open" do
    store_settings(:default).update!(black_friday_starts_at: 1.hour.ago, black_friday_ends_at: 1.hour.from_now)

    get root_path

    assert_select "head link[rel=stylesheet]:last-of-type[href*=?]", "themes/black-friday"
  end

  test "the home hero swaps to the black friday banner only while the window is open" do
    attach_banner(alt: "Destaque da loja")
    attach_banner(alt: "Black Friday Prisma Games", black_friday: true)

    get root_path
    assert_select "section.banner .banner__slot img", count: 1
    assert_select "section.banner .banner__slot img[alt=?]", "Destaque da loja"

    store_settings(:default).update!(black_friday_starts_at: 1.hour.ago)

    get root_path
    assert_select "section.banner .banner__slot img", count: 1
    assert_select "section.banner .banner__slot img[alt=?]", "Black Friday Prisma Games"
  end

  private

  def attach_banner(**attrs)
    HeroBanner.create!(position: 0, **attrs) do |banner|
      banner.image.attach(io: File.open(file_fixture("sample_product.jpg")),
                          filename: "hero.jpg", content_type: "image/jpeg")
    end
  end
end
