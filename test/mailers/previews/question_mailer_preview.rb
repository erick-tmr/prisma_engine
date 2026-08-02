class QuestionMailerPreview < ActionMailer::Preview
  def answered
    QuestionMailer.answered(Question.answered.where.not(answered_at: nil).first || Question.first)
  end

  def strike_first
    QuestionMailer.strike(strike_after(1))
  end

  def strike_second
    QuestionMailer.strike(strike_after(2))
  end

  def strike_permanent
    QuestionMailer.strike(strike_after(3))
  end

  private

  def strike_after(count)
    user_id = QuestionStrike.group(:user_id).having("count(*) = ?", count).pick(:user_id)
    QuestionStrike.where(user_id: user_id).chronological.last || QuestionStrike.first
  end
end
