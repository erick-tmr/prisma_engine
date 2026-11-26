module StorefrontThemeHelper
  BLACK_FRIDAY_STYLESHEET = "themes/black-friday".freeze

  def storefront_theme_stylesheet
    stylesheet_link_tag(BLACK_FRIDAY_STYLESHEET) if StoreSetting.current.black_friday?
  end
end
