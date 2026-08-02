class QuestionMailer < ApplicationMailer
  STRIKE_THEMES = {
    "first" => { accent: "#e08a00", panel_background: "#fff8ec", panel_border: "#f3e0bd", hero: "dragon-fly.png" },
    "second" => { accent: "#d64545", panel_background: "#fdf0f0", panel_border: "#f5cfcf", hero: "dragon-letter-full.png" },
    "permanent" => { accent: "#b3261e", panel_background: "#fdf0f0", panel_border: "#f5cfcf", hero: "dragon-face.png" }
  }.freeze

  def answered(question)
    @question = question
    @product = question.product
    mail(to: question.user.email, subject: default_i18n_subject(product: @product.name))
  end

  def strike(strike)
    @strike = strike
    @question = strike.question
    @ban = Questions::Ban.new(strike.user)
    @theme = STRIKE_THEMES.fetch(@ban.penalty)
    @blocked_until = @ban.expires_at && l(@ban.expires_at.to_date, format: :day_month_year)
    mail(to: strike.user.email, subject: t("question_mailer.strike.#{@ban.penalty}.subject"))
  end
end
