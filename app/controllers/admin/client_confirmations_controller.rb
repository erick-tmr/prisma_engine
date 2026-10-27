module Admin
  class ClientConfirmationsController < BaseController
    SCOPE = "admin.clients.detail.confirmation".freeze

    def create
      # nosemgrep: ruby.rails.security.brakeman.check-unscoped-find.check-unscoped-find -- backoffice: BaseController#require_admin gates the whole namespace, and an operator is meant to open any client
      client = User.clients.find(params[:client_id])
      outcome = client.confirmed? ? { alert: t("#{SCOPE}.already_confirmed") } : resend(client)
      # nosemgrep: ruby.rails.security.audit.xss.avoid-redirect.avoid-redirect -- internal path helper from a DB record, not a user-supplied URL
      redirect_to admin_client_path(client), **outcome
    end

    private

    def resend(client)
      client.confirmation_token = nil
      client.send_confirmation_instructions
      { notice: t("#{SCOPE}.sent", email: client.email) }
    end
  end
end
