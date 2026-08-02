require "test_helper"

class EmailHelperTest < ActionView::TestCase
  test "builds an R2 emails/ URL from the configured public host" do
    original = Rails.application.config.x.r2_public_host
    Rails.application.config.x.r2_public_host = "https://cdn.example.com/"

    assert_equal "https://cdn.example.com/emails/dragon-fly.png", email_asset_url("dragon-fly.png")
  ensure
    Rails.application.config.x.r2_public_host = original
  end

  test "falls back to a root-relative path when no public host is configured" do
    original = Rails.application.config.x.r2_public_host
    Rails.application.config.x.r2_public_host = nil

    assert_equal "/emails/prisma-games-logo.png", email_asset_url("prisma-games-logo.png")
  ensure
    Rails.application.config.x.r2_public_host = original
  end

  test "stamps a moment as a Brazilian date and time" do
    assert_equal "26/07/2026 às 09:14", email_datetime(Time.zone.local(2026, 7, 26, 9, 14))
  end

  test "stamps a moment as a Brazilian date, dropping the time" do
    assert_equal "28/07/2026", email_date(Time.zone.local(2026, 7, 28, 23, 50))
  end
end
