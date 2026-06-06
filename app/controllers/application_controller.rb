# CSRF protection is enabled globally by Rails 8 via
# config.action_controller.default_protect_from_forgery (set by load_defaults
# 8.0 in config/application.rb). Semgrep's missing-csrf-protection rule reads
# the controller statically and does not inspect framework config.
# nosemgrep: ruby.lang.security.missing-csrf-protection.missing-csrf-protection
class ApplicationController < ActionController::Base
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def render_not_found
    render "products/not_found", status: :not_found
  end
end
