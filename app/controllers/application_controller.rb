# CSRF protection is enabled globally by Rails 8 via
# config.action_controller.default_protect_from_forgery (set by load_defaults
# 8.0 in config/application.rb). Semgrep's missing-csrf-protection rule reads
# the controller statically and does not inspect framework config.
# nosemgrep: ruby.lang.security.missing-csrf-protection.missing-csrf-protection
class ApplicationController < ActionController::Base
  # Rails only exempts crawlers that name themselves inside a UA comment, which is
  # where the useragent gem looks. Meta appends "facebookexternalhit/1.1 Facebot
  # Twitterbot/1.0" as trailing products instead, so the Safari 9 it also reports
  # got the 406 page cached as our link preview.
  CRAWLER_USER_AGENT = /bot|crawler|spider|facebookexternalhit/i

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  allow_browser versions: { safari: 14, chrome: 86, firefox: 78, ie: false }, unless: :crawler?

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_cart, :current_cart_count

  private

  def crawler?
    CRAWLER_USER_AGENT.match?(request.user_agent.to_s)
  end

  def current_cart
    @current_cart ||= Cart::Bag.from_cookie(cookies.signed[:cart])
  end

  def current_cart_count
    current_cart.total_quantity
  end

  def render_not_found
    render "products/not_found", status: :not_found
  end
end
