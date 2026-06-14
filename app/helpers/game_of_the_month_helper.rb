module GameOfTheMonthHelper
  MONTH_NAMES = %w[
    Janeiro Fevereiro Março Abril Maio Junho
    Julho Agosto Setembro Outubro Novembro Dezembro
  ].freeze

  # pt-BR month name for a 1..12 month number (the DB constrains the range).
  def gotm_month_name(month)
    MONTH_NAMES.fetch(month.to_i - 1)
  end
end
