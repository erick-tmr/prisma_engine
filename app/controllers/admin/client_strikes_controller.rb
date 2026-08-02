module Admin
  class ClientStrikesController < BaseController
    def destroy
      # nosemgrep: ruby.rails.security.brakeman.check-unscoped-find.check-unscoped-find -- backoffice: BaseController#require_admin gates the whole namespace, and an operator is meant to open any client
      client = User.clients.find(params[:client_id])
      strike = client.question_strikes.find(params[:id])
      result = Questions::Moderate.call(question: strike.question, event: "release", actor: current_user)
      # nosemgrep: ruby.rails.security.audit.xss.avoid-redirect.avoid-redirect -- internal path helper from a DB record, not a user-supplied URL
      redirect_to admin_client_path(client), **flash_for(result)
    end

    private

    def flash_for(result)
      return { notice: t("admin.clients.detail.strikes.removed") } if result.done?

      { alert: t("admin.clients.detail.strikes.remove_failed") }
    end
  end
end
