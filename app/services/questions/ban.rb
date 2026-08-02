module Questions
  class Ban
    DURATIONS = [ 1.week, 1.month ].freeze
    PENALTIES = %w[first second].freeze
    PERMANENT_AFTER = DURATIONS.size + 1

    def initialize(user)
      @user = user
    end

    def strikes
      @strikes ||= @user.question_strikes.count
    end

    def permanent?
      strikes >= PERMANENT_AFTER
    end

    def expires_at
      return if permanent? || strikes.zero?

      @user.question_strikes.chronological.last.created_at + DURATIONS[strikes - 1]
    end

    def active?
      return false if strikes.zero?

      permanent? || expires_at.future?
    end

    def penalty
      penalty_for(strikes)
    end

    def next_penalty
      penalty_for(strikes + 1)
    end

    private

    def penalty_for(count)
      count >= PERMANENT_AFTER ? "permanent" : PENALTIES[count - 1]
    end
  end
end
