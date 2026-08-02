class QuestionMailerPreview < ActionMailer::Preview
  def answered
    QuestionMailer.answered(Question.answered.first || Question.first)
  end

  def strike
    QuestionMailer.strike(QuestionStrike.first || QuestionStrike.new(
      user: Question.first.user, question: Question.first, issued_by: User.where(admin: true).first
    ))
  end
end
