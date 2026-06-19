require "simplecov"
require "undercover/simplecov_formatter"

SimpleCov.start "rails" do
  enable_coverage :branch
  add_filter "/test/"
  # Devise views are templated above (Bootstrap 5 + i18n) but Rails 8 view
  # coverage would otherwise drag them into the 100% floor for branches we
  # don't introduce ourselves — system tests still exercise them end-to-end.
  add_filter "/app/views/devise/"

  # 100% floor — the suite refuses to pass below full line and branch coverage.
  # Combined with undercover (changed-line gate), this enforces both "every
  # changed line is tested" and "no regressions in existing coverage." Mark
  # genuinely untestable lines (Rails scaffold stubs, defensive guards behind
  # route constraints) with `# :nocov:` and a comment explaining why.
  #
  # The floor is the contract of the unit+integration run (`bin/rails test`),
  # which alone reaches 100%. The separate `bin/rails test:system` run drives
  # only a handful of critical paths through the whole app, so it must NOT assert
  # the floor — CI sets SKIP_COVERAGE_FLOOR=1 on the system-test job, and local
  # `bin/rails test:system` does the same.
  minimum_coverage(line: 100, branch: 100) unless ENV["SKIP_COVERAGE_FLOOR"]

  # HTML for humans + Undercover's JSON formatter (coverage/coverage.json), which
  # the `undercover` CLI reads to flag changed lines that lack test coverage.
  # SimpleCov also writes coverage/.last_run.json (total line/branch %) for the
  # PR summary.
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::Undercover
  ])
end

# System runs measure a different slice of the app than the unit run; give them
# a distinct base name so their results never overwrite the unit/integration
# coverage the undercover job consumes.
SimpleCov.command_name("system") if ENV["SKIP_COVERAGE_FLOOR"]

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# No test may reach the network. Correios rastro calls are stubbed with WebMock;
# localhost stays open for Capybara/Cuprite system tests.
require "webmock/minitest"
WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Once the suite crosses the parallelization threshold it forks workers, and
    # SimpleCov tracks coverage per process. Give each worker a unique result name
    # and flush its result on teardown so the parent merges them — otherwise the
    # merged coverage.json undercover reads looks nearly empty.
    parallelize_setup do |worker|
      SimpleCov.command_name "#{SimpleCov.command_name}-#{worker}"
    end

    parallelize_teardown do |_worker|
      SimpleCov.result
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
