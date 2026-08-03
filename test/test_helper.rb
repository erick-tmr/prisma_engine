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

    SPARE_CPFS = %w[52987411340 61829374591 70345182626 81572639482].freeze

    def count_queries
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name].to_s.match?(/SCHEMA|TRANSACTION/) }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
      count
    end

    def with_canonical_host(host)
      previous = Rails.application.config.x.canonical_host
      Rails.application.config.x.canonical_host = host
      yield
    ensure
      Rails.application.config.x.canonical_host = previous
    end

    # Spam strikes are deliberately kept out of the shared fixtures: they would
    # shift the question counts and the oldest/newest ordering every other test
    # asserts on. Each caller builds the ban state it needs, inside its own
    # transaction. The questions span distinct products in distinct categories so
    # a missing preload shows up as an N+1 instead of hiding behind one shared row.
    STRIKE_PRODUCTS = %i[yellow metroid plastic_shell].freeze

    def client_with_strikes(count, name:, cpf:, last_strike_at: Time.current)
      client = User.create!(full_name: name, email: "#{cpf}@example.com", cpf: cpf,
                            phone: "11900000000", password: "password123", confirmed_at: 2.days.ago)

      count.times do |index|
        question = Question.create!(product: products(STRIKE_PRODUCTS[index % STRIKE_PRODUCTS.size]),
                                    user: client, status: "spam",
                                    body: "Compre no meu perfil, sai bem mais barato que aqui. (#{index})")
        QuestionStrike.create!(user: client, question: question, issued_by: users(:admin))
                      .update_column(:created_at, last_strike_at - (count - index - 1).days)
      end

      client
    end
  end
end
