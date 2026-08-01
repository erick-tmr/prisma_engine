module Admin
  class QuestionBulkAction
    EVENTS = %w[archive spam release].freeze

    def self.call(ids:, event:, actor:)
      new(ids: ids, event: event, actor: actor).call
    end

    def initialize(ids:, event:, actor:)
      @ids = Array(ids)
      @event = event.to_s
      @actor = actor
    end

    def call
      summarize(EVENTS.include?(@event) ? questions.map { |question| moderate(question) } : unknown_event)
    end

    private

    def questions
      Question.where(id: @ids).includes(:user)
    end

    def moderate(question)
      result = Questions::Moderate.call(question: question, event: @event, actor: @actor)
      row(question, result.outcome, result.reason)
    end

    def unknown_event
      questions.map { |question| row(question, "skipped", "unknown_event") }
    end

    def row(question, outcome, reason)
      { "id" => question.id, "outcome" => outcome, "status" => question.status, "reason" => reason }
    end

    def summarize(results)
      {
        "event" => @event,
        "results" => results,
        "done" => results.count { |result| result["outcome"] == "done" },
        "skipped" => results.count { |result| result["outcome"] == "skipped" }
      }
    end
  end
end
