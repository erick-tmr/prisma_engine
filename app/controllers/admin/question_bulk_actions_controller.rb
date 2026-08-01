module Admin
  class QuestionBulkActionsController < BaseController
    def create
      result = Admin::QuestionBulkAction.call(
        ids: params[:question_ids],
        event: params[:event],
        actor: current_user
      )
      render json: result.merge("message" => message_for(result))
    end

    private

    def message_for(result)
      event = params[:event].to_s
      event = "unknown" unless Admin::QuestionBulkAction::EVENTS.include?(event)
      t("admin.questions.bulk.done.#{event}", count: result["done"])
    end
  end
end
