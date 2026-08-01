module Admin
  class QuestionsController < BaseController
    include QuestionListRedirect

    def index
      @search = Admin::QuestionSearch.new(params)
      @base_params = @search.to_params
      @page = Admin::Page.new(@search.relation, page_param)
      @questions = @page.rows
      @question = drawer_question
      @canned = CannedAnswer.ordered
      render_list "results"
    end

    def update
      result = Questions::Moderate.call(question: find_question, event: params[:event],
                                        actor: current_user, answer_body: params[:answer_body])
      redirect_to question_list_path(pergunta: nil), **flash_for(result)
    end

    private

    def find_question
      # nosemgrep: ruby.rails.security.brakeman.check-unscoped-find.check-unscoped-find
      Question.find(params[:id])
    end

    def drawer_question
      return if params[:pergunta].blank?

      Question.includes(:user, :question_strike, product: :category).find_by(id: params[:pergunta])
    end

    def flash_for(result)
      return { notice: t("admin.questions.flash.#{params[:event]}") } if result.done?

      { alert: t("admin.questions.errors.#{result.reason}") }
    end
  end
end
