# Hardens the dev server when SHARE_MODE=1 so it can be exposed via a public
# tunnel (Cloudflare/ngrok) without leaking source code or shells. Pairs with
# the SHARE_MODE block in config/environments/development.rb.
#
# Wires:
#   - HTTP Basic auth (constant-time compare, requires SHARE_AUTH_USER /
#     SHARE_AUTH_PASSWORD; pw must be at least 16 chars)
#   - Path blocker that 404s dev-only Rails introspection routes
#     (/rails/info/*, /rails/conductor/*, /rails/mailers/*) regardless of auth
#   - Removes the WebConsole middleware entirely as belt-and-suspenders against
#     a tunneled request appearing local
return unless ENV["SHARE_MODE"] == "1"

require "rack/auth/basic"
require "active_support/security_utils"
require "digest"

share_user = ENV.fetch("SHARE_AUTH_USER")
share_pass = ENV.fetch("SHARE_AUTH_PASSWORD")

if share_pass.bytesize < 16
  raise "SHARE_AUTH_PASSWORD must be at least 16 characters when SHARE_MODE=1 " \
        "(got #{share_pass.bytesize})"
end

class BlockDevIntrospection
  BLOCKED_PREFIXES = %w[
    /rails/info
    /rails/conductor
    /rails/mailers
    /rails/db
  ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    path = env["PATH_INFO"].to_s
    if BLOCKED_PREFIXES.any? { |prefix| path == prefix || path.start_with?("#{prefix}/") }
      [404, { "content-type" => "text/plain" }, ["Not found"]]
    else
      @app.call(env)
    end
  end
end

Rails.application.config.middleware.insert_before(
  ActionDispatch::HostAuthorization, BlockDevIntrospection
)

Rails.application.config.middleware.insert_before(
  ActionDispatch::HostAuthorization,
  Rack::Auth::Basic,
  "Prisma Games — preview"
) do |user, pass|
  ActiveSupport::SecurityUtils.secure_compare(
    ::Digest::SHA256.hexdigest(user.to_s),
    ::Digest::SHA256.hexdigest(share_user)
  ) & ActiveSupport::SecurityUtils.secure_compare(
    ::Digest::SHA256.hexdigest(pass.to_s),
    ::Digest::SHA256.hexdigest(share_pass)
  )
end

if defined?(WebConsole::Middleware)
  Rails.application.config.middleware.delete(WebConsole::Middleware)
end
