module StructuredLogging
  class ActiveJobLogSubscriber < ActiveSupport::LogSubscriber
    OUTCOMES = {
      "enqueue" => { ok: "enqueued", error: "enqueue_failed" },
      "enqueue_at" => { ok: "scheduled", error: "enqueue_failed" },
      "perform" => { ok: "performed", error: "errored" },
      "enqueue_retry" => { ok: "retry_scheduled", error: "retry_scheduled" },
      "retry_stopped" => { ok: "retries_exhausted", error: "retries_exhausted" },
      "discard" => { ok: "discarded", error: "discarded" }
    }.freeze

    def self.install
      ActiveJob::LogSubscriber.detach_from :active_job
      attach_to :active_job
    end

    OUTCOMES.each_key do |name|
      define_method(name) { |event| emit(event) }
    end

    def initialize
      super
      @param_filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    end

    private

    # :reek:FeatureEnvy reads fields off the Active Job event and its job.
    def emit(event)
      job = event.payload[:job]
      error = event.payload[:exception_object] || event.payload[:error]
      job_event = event.name.split(".").first
      logger.info JSON.dump({
        time: Time.now.utc.iso8601(3),
        event: "job",
        job_event: job_event,
        job_class: job.class.name,
        job_id: job.job_id,
        queue: job.queue_name,
        outcome: OUTCOMES.dig(job_event, error ? :error : :ok),
        duration: event.duration.round(2),
        executions: job.executions,
        arguments: loggable_arguments(job),
        exception: error&.class&.name,
        exception_message: error&.message
      }.compact)
    end

    def loggable_arguments(job)
      return unless job.class.log_arguments? && job.arguments.any?

      @param_filter.filter(arguments: identify(job.arguments)).fetch(:arguments)
    end

    # Replace records with their GlobalID so attributes never reach the log; PII
    # inside option hashes is then redacted by the parameter filter in #loggable_arguments.
    def identify(argument)
      case argument
      when Hash then argument.transform_values { |value| identify(value) }
      when Array then argument.map { |value| identify(value) }
      when GlobalID::Identification then argument.to_global_id.to_s
      else argument
      end
    end
  end
end
