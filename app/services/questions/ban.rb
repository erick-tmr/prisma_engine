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

    def last_strike
      @last_strike ||= @user.question_strikes.chronological.includes(question: :product).last
    end

    def expires_at
      return if permanent? || strikes.zero?

      last_strike.created_at + DURATIONS[strikes - 1]
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

    def final_warning?
      strikes == PENALTIES.size
    end

    def ladder
      @ladder ||= begin
        reached = @user.question_strikes.chronological.pluck(:created_at)

        (1..PERMANENT_AFTER).map do |ordinal|
          { ordinal: ordinal, penalty: penalty_for(ordinal), reached_at: reached[ordinal - 1] }
        end
      end
    end

    def penalty_for(count)
      count >= PERMANENT_AFTER ? "permanent" : PENALTIES[count - 1]
    end
  end
end
