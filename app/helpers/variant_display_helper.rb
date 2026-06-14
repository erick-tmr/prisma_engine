module VariantDisplayHelper
  GROUP_ICONS = {
    "Idioma" => "bi-translate",
    "Caixa"  => "bi-box2",
    "Label"  => "bi-tag"
  }.freeze
  GROUP_ICON_FALLBACK = "bi-sliders2".freeze

  LANGUAGE_FLAGS = {
    "Inglês"        => "🇺🇸",
    "Português BR"  => "🇧🇷",
    "Português"     => "🇧🇷",
    "Japonês"       => "🇯🇵"
  }.freeze

  def variant_group_icon(group_name)
    GROUP_ICONS.fetch(group_name.to_s, GROUP_ICON_FALLBACK)
  end

  def variant_option_flag(option_name)
    LANGUAGE_FLAGS[option_name.to_s]
  end

  def variant_delta_label(price_delta_cents)
    cents = price_delta_cents.to_i
    return if cents.zero?

    "#{cents.negative? ? '−' : '+'}#{HasMoney.format(cents.abs)}"
  end
end
