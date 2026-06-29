require "test_helper"

module StructuredLogging
  class ActiveJobLogSubscriberTest < ActiveSupport::TestCase
    class SampleJob < ActiveJob::Base; end
    class QuietJob < ActiveJob::Base
      self.log_arguments = false
    end

    class FakeRecord
      include GlobalID::Identification
      def id = 42
    end

    FakeEvent = Struct.new(:name, :payload, :duration)

    setup do
      @io = StringIO.new
      logger = ActiveSupport::Logger.new(@io)
      logger.formatter = proc { |_severity, _time, _progname, message| "#{message}\n" }
      @subscriber = ActiveJobLogSubscriber.new
      @subscriber.instance_variable_set(:@logger, logger)
    end

    test "perform emits one JSON line with the performed outcome and no exception" do
      line = log_line(:perform, job: build_job(executions: 2, queue: "mailers"))

      assert_equal "job", line["event"]
      assert_equal "perform", line["job_event"]
      assert_equal SampleJob.name, line["job_class"]
      assert_equal "mailers", line["queue"]
      assert_equal "performed", line["outcome"]
      assert_equal 2, line["executions"]
      assert_in_delta 12.34, line["duration"], 0.001
      assert line["job_id"].present?
      assert line["time"].present?
      assert_not line.key?("exception")
      assert_not line.key?("exception_message")
    end

    test "perform with a raised exception reports the errored outcome and the error" do
      line = log_line(:perform, job: build_job, exception_object: RuntimeError.new("boom"))

      assert_equal "errored", line["outcome"]
      assert_equal "RuntimeError", line["exception"]
      assert_equal "boom", line["exception_message"]
    end

    test "enqueue maps to the enqueued outcome" do
      assert_equal "enqueued", log_line(:enqueue, job: build_job)["outcome"]
    end

    test "enqueue failure maps to the enqueue_failed outcome" do
      line = log_line(:enqueue, job: build_job, exception_object: RuntimeError.new("nope"))

      assert_equal "enqueue_failed", line["outcome"]
    end

    test "enqueue_at maps to the scheduled outcome" do
      assert_equal "scheduled", log_line(:enqueue_at, job: build_job)["outcome"]
    end

    test "enqueue_retry reads the error from the payload error key" do
      line = log_line(:enqueue_retry, job: build_job, error: StandardError.new("flaky"))

      assert_equal "retry_scheduled", line["outcome"]
      assert_equal "StandardError", line["exception"]
      assert_equal "flaky", line["exception_message"]
    end

    test "retry_stopped maps to the retries_exhausted outcome" do
      line = log_line(:retry_stopped, job: build_job, error: StandardError.new("done"))

      assert_equal "retries_exhausted", line["outcome"]
    end

    test "discard maps to the discarded outcome" do
      line = log_line(:discard, job: build_job, error: StandardError.new("gone"))

      assert_equal "discarded", line["outcome"]
    end

    test "logs job arguments with PII keys redacted by the parameter filter" do
      line = log_line(:perform, job: build_job(arguments: [ "plain", { email: "a@b.com", id: 5 } ]))

      assert_equal "plain", line["arguments"][0]
      assert_equal "[FILTERED]", line["arguments"][1]["email"]
      assert_equal 5, line["arguments"][1]["id"]
    end

    test "logs record arguments as global ids, never their attributes" do
      line = log_line(:perform, job: build_job(arguments: [ FakeRecord.new ]))

      assert_match %r{\Agid://}, line["arguments"][0]
    end

    test "omits arguments when the job opts out via log_arguments" do
      line = log_line(:perform, job: build_job(arguments: [ "x" ], klass: QuietJob))

      assert_not line.key?("arguments")
    end

    test "omits arguments when the job has none" do
      assert_not log_line(:perform, job: build_job(arguments: [])).key?("arguments")
    end

    test "writes to a dedicated non-tagged logger so Active Job tags never prefix the JSON" do
      assert_not ActiveJobLogSubscriber.new.logger.respond_to?(:tagged)
    end

    test "install detaches the default Active Job subscriber and attaches itself" do
      detached = nil
      attached = nil

      ActiveJob::LogSubscriber.stub(:detach_from, ->(namespace) { detached = namespace }) do
        ActiveJobLogSubscriber.stub(:attach_to, ->(namespace) { attached = namespace }) do
          ActiveJobLogSubscriber.install
        end
      end

      assert_equal :active_job, detached
      assert_equal :active_job, attached
    end

    private

    def build_job(arguments: [], executions: 1, queue: "default", klass: SampleJob)
      job = klass.new(*arguments)
      job.executions = executions
      job.queue_name = queue
      job
    end

    def log_line(method_name, payload)
      event = FakeEvent.new("#{method_name}.active_job", payload, 12.34)
      @subscriber.public_send(method_name, event)
      JSON.parse(@io.string.lines.last)
    end
  end
end
