require "test_helper"

module Admin
  class CannedAnswersControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    test "non-admins are sent to the backoffice login" do
      post admin_canned_answers_path, params: { canned_answer: { label: "Frete", body: "Enviamos para todo o Brasil." } }

      assert_redirected_to admin_login_path
    end

    test "creating a shortcut returns to the manager with the list filters intact" do
      sign_in users(:admin)

      assert_difference -> { CannedAnswer.count }, 1 do
        post admin_canned_answers_path, params: {
          canned_answer: { label: "Frete e rastreio", body: "Enviamos para todo o Brasil por PAC e SEDEX." },
          status: "spam", q: "cabo"
        }
      end

      assert_redirected_to admin_questions_path(q: "cabo", status: "spam", respostas: "1")
      assert_equal "Atalho Frete e rastreio criado, já aparece para toda a equipe.", flash[:notice]
    end

    test "an invalid shortcut comes back with the reason instead of saving" do
      sign_in users(:admin)

      assert_no_difference -> { CannedAnswer.count } do
        post admin_canned_answers_path, params: { canned_answer: { label: "", body: "curto" } }
      end

      assert_redirected_to admin_questions_path(respostas: "1")
      assert_match(/não pode ficar em branco/, flash[:alert])
    end

    test "editing a shortcut rewrites it for the whole team" do
      canned = canned_answers(:compatibility)
      sign_in users(:admin)
      patch admin_canned_answer_path(canned), params: {
        canned_answer: { label: "Compatibilidade GBA", body: "Roda no Game Boy Advance e no GBA SP sem adaptador." }
      }

      assert_redirected_to admin_questions_path(respostas: "1")
      assert_equal "Roda no Game Boy Advance e no GBA SP sem adaptador.", canned.reload.body
    end

    test "deleting a shortcut takes it off the composer" do
      sign_in users(:admin)

      assert_difference -> { CannedAnswer.count }, -1 do
        delete admin_canned_answer_path(canned_answers(:production_time))
      end

      assert_equal "Atalho Prazo de produção excluído.", flash[:notice]
    end

    test "the manager reopens on the question the operator was answering" do
      question = questions(:awaiting_yellow)
      sign_in users(:admin)
      post admin_canned_answers_path, params: {
        canned_answer: { label: "Garantia", body: "Noventa dias de garantia contra defeito." },
        pergunta: question.id.to_s
      }

      assert_redirected_to admin_questions_path(pergunta: question.id.to_s, respostas: "1")
    end
  end
end
