require "test_helper"
require "capybara/cuprite"

Dir[Rails.root.join("test/system/support/**/*.rb")].each { |file| require file }

Capybara.default_max_wait_time = 2
Capybara.disable_animation     = true
Capybara.save_path             = Rails.root.join("tmp/screenshots")

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include Warden::Test::Helpers
  include SystemStubs

  EXTERNAL_HOSTS = [
    %r{//(api\.)?checkout\.infinitepay\.io},
    %r{\.correios\.com\.br},
    %r{meloja},
    %r{prismagames\.com\.br}
  ].freeze

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

  def login_as_user(user)
    login_as(user, scope: :user)
  end
end
