class QuestionMailer < ApplicationMailer
  def answered(question)
    @question = question
    @product = question.product
    mail(to: question.user.email, subject: default_i18n_subject(product: @product.name))
  end

  def strike(strike)
    @strike = strike
    @question = strike.question
    @ban = Questions::Ban.new(strike.user)
    @blocked_until = @ban.expires_at && l(@ban.expires_at.to_date)
    mail(to: strike.user.email, subject: default_i18n_subject)
  end
end
