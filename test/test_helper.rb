require "simplecov"
require "undercover/simplecov_formatter"

SimpleCov.start "rails" do
  enable_coverage :branch
  skip "/test/"
  skip "/app/views/devise/"

  # route constraints) with `# :nocov:` and a comment explaining why.
  minimum_coverage(line: 100, branch: 100) unless ENV["SKIP_COVERAGE_FLOOR"]

  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::Undercover
  ])
end

SimpleCov.command_name("system") if ENV["SKIP_COVERAGE_FLOOR"]

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

require "webmock/minitest"
WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    parallelize_setup do |worker|
      SimpleCov.command_name "#{SimpleCov.command_name}-#{worker}"
    end

    parallelize_teardown do |_worker|
      SimpleCov.result
    end

    fixtures :all

    def with_canonical_host(host)
      previous = Rails.application.config.x.canonical_host
      Rails.application.config.x.canonical_host = host
      yield
    ensure
      Rails.application.config.x.canonical_host = previous
    end
  end
end
