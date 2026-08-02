module ApplicationHelper
  PG_ALERT_VARIANTS = {
    "notice" => { variant: "info",    icon: "bi-info-circle-fill" },
    "cart_added" => { variant: "success", icon: "bi-cart-check-fill" },
    "success" => { variant: "success", icon: "bi-check-circle-fill" },
    "alert" => { variant: "warning", icon: "bi-exclamation-triangle-fill" },
    "error" => { variant: "danger",  icon: "bi-exclamation-octagon-fill" }
  }.freeze

  PG_ALERT_FALLBACK = { variant: "info", icon: "bi-info-circle-fill" }.freeze

  def pg_alert_meta(key)
    PG_ALERT_VARIANTS.fetch(key.to_s, PG_ALERT_FALLBACK)
  end

  def canonical_url
    host = Rails.application.config.x.canonical_host.presence || request.host
    "#{request.scheme}://#{host}#{request.path}"
  end

  def relative_time_ago(time)
    t("products.questions.time_ago", time: time_ago_in_words(time))
  end
end
