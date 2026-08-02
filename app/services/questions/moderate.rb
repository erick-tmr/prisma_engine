module Questions
  class Moderate
    EVENTS = %w[answer draft archive spam release].freeze

    Result = Data.define(:question, :outcome, :reason) do
      def done?
        outcome == "done"
      end
    end

    def self.call(question:, event:, actor:, answer_body: nil)
      new(question: question, event: event, actor: actor, answer_body: answer_body).call
    end

    def initialize(question:, event:, actor:, answer_body: nil)
      @question = question
      @event = event.to_s
      @actor = actor
      @answer_body = answer_body.to_s.strip
    end

    def call
      case @event
      when "answer"  then publish_answer
      when "draft"   then save_draft
      when "archive" then move_to("archived")
      when "spam"    then mark_spam
      when "release" then release
      else skipped("unknown_event")
      end
    end

    private

    def publish_answer
      return skipped("blank_answer") if @answer_body.blank?

      @question.update!(answer_body: @answer_body, status: "answered")
      done
    end

    def save_draft
      return move_to("awaiting_answer", answer_body: nil) if @answer_body.blank?

      @question.update!(answer_body: @answer_body, status: "draft")
      done
    end

    def mark_spam
      return skipped("already_spam") if @question.spam?

      ActiveRecord::Base.transaction do
        @question.update!(status: "spam")
        QuestionStrike.create!(user: @question.user, question: @question, issued_by: @actor)
      end
      done
    end

    def release
      return skipped("not_moderated") unless @question.spam? || @question.archived?

      ActiveRecord::Base.transaction do
        @question.question_strike&.destroy!
        move_to(@question.answer_body.present? ? "draft" : "awaiting_answer")
      end
    end

    def move_to(status, answer_body: :keep)
      attributes = { status: status }
      attributes[:answer_body] = answer_body unless answer_body == :keep
      @question.update!(attributes)
      done
    end

    def done
      Result.new(question: @question, outcome: "done", reason: nil)
    end

    def skipped(reason)
      Result.new(question: @question, outcome: "skipped", reason: reason)
    end
  end
end
