module Products
  class QuestionsController < ApplicationController
    before_action :load_product
    before_action :require_signed_in_customer
    before_action :require_asking_privileges

    rate_limit to: 5, within: 1.hour, by: -> { current_user.id },
               with: :too_many_questions, only: :create

    def create
      question = @product.questions.build(question_params.merge(user: current_user))

      if question.save
        flash[:success] = t("products.questions.created")
      else
        flash[:error] = question.errors.full_messages.to_sentence
      end

      redirect_to_questions
    end

    private

    def load_product
      # nosemgrep: ruby.rails.security.brakeman.check-unscoped-find.check-unscoped-find
      @product = Product.friendly.find(params[:slug])
      raise ActiveRecord::RecordNotFound unless @product.published?
    end

    def question_params
      params.expect(question: [ :body ])
    end

    def require_signed_in_customer
      return if user_signed_in?

      session["user_return_to"] = product_questions_anchor
      redirect_to new_user_session_path, notice: t("products.questions.sign_in_required")
    end

    def require_asking_privileges
      ban = Questions::Ban.new(current_user)
      return unless ban.active?

      flash[:alert] = t("products.questions.blocked.#{ban.penalty}",
                        date: ban.expires_at && l(ban.expires_at.to_date))
      redirect_to_questions
    end

    def too_many_questions
      flash[:alert] = t("products.questions.throttled")
      redirect_to_questions
    end

    def redirect_to_questions
      redirect_to product_questions_anchor
    end

    def product_questions_anchor
      product_path(@product, anchor: "perguntas")
    end
  end
end
