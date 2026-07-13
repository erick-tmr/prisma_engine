module GameOfTheMonthHelper
  MONTH_NAMES = %w[
    Janeiro Fevereiro Março Abril Maio Junho
    Julho Agosto Setembro Outubro Novembro Dezembro
  ].freeze

  def gotm_month_name(month)
    MONTH_NAMES.fetch(month.to_i - 1)
  end

  def gotm_band_cache_key(gotm)
    parts = gotm.game_of_the_month_products.map do |pick|
      [ pick, pick.product, pick.product.image, pick.brindes.to_a ]
    end
    [ "gotm-band", gotm, parts ]
  end
end
