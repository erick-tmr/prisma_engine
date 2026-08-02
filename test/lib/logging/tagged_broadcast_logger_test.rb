require "test_helper"
require Rails.root.join("lib/logging/tagged_broadcast_logger")

module Logging
  class TaggedBroadcastLoggerTest < ActiveSupport::TestCase
    setup do
      @stdout_sink = StringIO.new
      @file_sink = StringIO.new
      @logger = Logging::TaggedBroadcastLogger.new(
        ActiveSupport::TaggedLogging.logger(@stdout_sink),
        ActiveSupport::TaggedLogging.logger(@file_sink)
      )
    end

    test "runs the block once no matter how many sinks it broadcasts to" do
      runs = 0

      @logger.tagged("Job") { runs += 1 }

      assert_equal 1, runs
    end

    test "the stock BroadcastLogger runs it once per sink, which is the bug this exists for" do
      runs = 0

      ActiveSupport::BroadcastLogger.new(
        ActiveSupport::TaggedLogging.logger(StringIO.new),
        ActiveSupport::TaggedLogging.logger(StringIO.new)
      ).tagged("Job") { runs += 1 }

      assert_equal 2, runs
    end

    test "still stamps the tag on every sink" do
      @logger.tagged("WelcomeMailer") { @logger.info("delivered") }

      assert_includes @stdout_sink.string, "[WelcomeMailer] delivered"
      assert_includes @file_sink.string, "[WelcomeMailer] delivered"
    end

    test "nests every tag it was handed" do
      @logger.tagged("A", "B") { @logger.info("x") }

      assert_includes @stdout_sink.string, "[A] [B] x"
    end

    test "a sink that cannot be tagged does not stop the block from running" do
      runs = 0
      logger = Logging::TaggedBroadcastLogger.new(Logger.new(StringIO.new))

      logger.tagged("Job") { runs += 1 }

      assert_equal 1, runs
    end

    test "without a block it keeps the stock behaviour" do
      assert_nothing_raised { @logger.tagged("Job") }
    end
  end
end
