class ApplicationController < ActionController::Base
  # Defense in depth — Rails 8 also enables this globally via
  # config.action_controller.default_protect_from_forgery.
  protect_from_forgery with: :exception

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
end
