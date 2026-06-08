module Users
  class ConfirmationsController < Devise::ConfirmationsController
    # Surface `?email=...` so the post-registration redirect can pre-fill the
    # confirm-email page with the pill (instead of asking the user to type it
    # back). When the page is visited cold (no email param), the view falls
    # back to an input field.
    def new
      super
      @email = params[:email].presence
    end
  end
end
