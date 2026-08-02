module QuestionListRedirect
  extend ActiveSupport::Concern

  LIST_KEYS = %i[q status produto sort page pergunta].freeze

  private

  def question_list_path(extra = {})
    kept = params.permit(*LIST_KEYS).to_h.symbolize_keys
    admin_questions_path(kept.merge(extra).compact_blank)
  end
end
