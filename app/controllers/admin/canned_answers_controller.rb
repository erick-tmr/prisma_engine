module Admin
  class CannedAnswersController < BaseController
    include QuestionListRedirect

    before_action :set_canned_answer, only: %i[update destroy]

    def create
      persist(CannedAnswer.new(canned_answer_params), "created")
    end

    def update
      @canned_answer.assign_attributes(canned_answer_params)
      persist(@canned_answer, "updated")
    end

    def destroy
      @canned_answer.destroy!
      back_to_manager(notice: t("admin.questions.canned.flash.destroyed", label: @canned_answer.label))
    end

    private

    def set_canned_answer
      # nosemgrep: ruby.rails.security.brakeman.check-unscoped-find.check-unscoped-find
      @canned_answer = CannedAnswer.find(params[:id])
    end

    def persist(canned_answer, key)
      return back_to_manager(alert: canned_answer.errors.full_messages.to_sentence) unless canned_answer.save

      back_to_manager(notice: t("admin.questions.canned.flash.#{key}", label: canned_answer.label))
    end

    def back_to_manager(flash_message)
      redirect_to question_list_path(respostas: "1"), **flash_message
    end

    def canned_answer_params
      params.expect(canned_answer: [ :label, :body ])
    end
  end
end
