require_relative "../../lib/middleware/maintenance"

if ENV["MAINTENANCE_MODE"].present?
  Rails.application.config.middleware.insert_before 0, Middleware::Maintenance,
    page_path: Rails.root.join("public/maintenance.html"),
    allowed_ips: ENV.fetch("MAINTENANCE_ALLOW_IPS", "").split(",").map(&:strip).compact_blank,
    passthrough: [ %r{\A/up\z}, %r{\A/pagamentos/webhook/}, %r{\A/images/} ]
end
