require "test_helper"
require "capybara/cuprite"

# Shared stubs for the external services system tests exercise (Correios, InfinitePay).
Dir[Rails.root.join("test/system/support/**/*.rb")].each { |file| require file }

# Cuprite is fast enough that the default 2s wait is plenty; don't crank it to
# paper over races. Killing CSS transitions stops visibility waits from racing
# Bootstrap animations. Screenshots land where the CI artifact step expects them.
Capybara.default_max_wait_time = 2
Capybara.disable_animation     = true
Capybara.save_path             = Rails.root.join("tmp/screenshots")

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include Warden::Test::Helpers
  include SystemStubs

  # No browser request may reach a third party. WebMock fences the Ruby side
  # (server → Correios/InfinitePay); this fences the browser side — the
  # InfinitePay payment popup and any stray external asset. data:/about:/blob:
  # are not network requests, so they load regardless of the blocklist.
  # Override with DENY_EXTERNAL=0 when debugging.
  EXTERNAL_HOSTS = [
    %r{//(api\.)?checkout\.infinitepay\.io},
    %r{\.correios\.com\.br},
    %r{meloja},
    %r{prismagames\.com\.br}
  ].freeze

  # One headless Chrome at a time: N browsers on a 2-core CI runner invites
  # OOM/flake and contended CDP sockets. The suite is intentionally thin.
  parallelize(workers: 1)

  driven_by :cuprite, screen_size: [ 1400, 1000 ], options: {
    headless:        ENV["HEADLESS"] != "0",
    process_timeout: 20,
    timeout:         15,
    js_errors:       true,
    browser_options: ENV["CI"] ? { "no-sandbox" => nil } : {},
    url_blacklist:   ENV["DENY_EXTERNAL"] == "0" ? [] : EXTERNAL_HOSTS
  }

  setup    { Warden.test_mode! }
  teardown { Warden.test_reset! }

  # Sign a user in without driving the Devise form — for specs not testing auth
  # itself. The auth specs use the real /entrar and /cadastrar forms instead.
  def login_as_user(user)
    login_as(user, scope: :user)
  end
end
