require "simplecov"
require "undercover/simplecov_formatter"

SimpleCov.start "rails" do
  enable_coverage :branch
  add_filter "/test/"

  # 100% floor — the suite refuses to pass below full line and branch coverage.
  # Combined with undercover (changed-line gate), this enforces both "every
  # changed line is tested" and "no regressions in existing coverage." Mark
  # genuinely untestable lines (Rails scaffold stubs, defensive guards behind
  # route constraints) with `# :nocov:` and a comment explaining why.
  minimum_coverage line: 100, branch: 100

  # HTML for humans + Undercover's JSON formatter (coverage/coverage.json), which
  # the `undercover` CLI reads to flag changed lines that lack test coverage.
  # SimpleCov also writes coverage/.last_run.json (total line/branch %) for the
  # PR summary.
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::Undercover
  ])
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# No test may reach the network. Correios rastro calls are stubbed with WebMock;
# localhost stays open for Capybara/Selenium system tests.
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
