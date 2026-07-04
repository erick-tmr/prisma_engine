module VariantDisplayHelper
  GROUP_ICONS = {
    "Idioma" => "bi-translate",
    "Caixa"  => "bi-box2",
    "Label"  => "bi-tag"
  }.freeze
  GROUP_ICON_FALLBACK = "bi-sliders2".freeze

  LANGUAGES = {
    "Inglês"        => { flag: "🇺🇸", slug: "en" },
    "Português BR"  => { flag: "🇧🇷", slug: "br" },
    "Português"     => { flag: "🇧🇷", slug: "br" },
    "Japonês"       => { flag: "🇯🇵", slug: "jp" }
  }.freeze

  def variant_group_icon(group_name)
    GROUP_ICONS.fetch(group_name.to_s, GROUP_ICON_FALLBACK)
  end

  def variant_option_flag(option_name)
    LANGUAGES.dig(option_name.to_s, :flag)
  end

  def variant_language_slug(option_name)
    LANGUAGES.dig(option_name.to_s, :slug)
  end
end
