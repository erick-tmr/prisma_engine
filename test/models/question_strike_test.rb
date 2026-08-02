require "test_helper"

class QuestionStrikeTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "a strike belongs to the author, the question and the operator who issued it" do
    strike = question_strikes(:spam_yellow_buyer)

    assert_equal users(:buyer), strike.user
    assert_equal questions(:spam_yellow), strike.question
    assert_equal users(:admin), strike.issued_by
  end

  test "a question cannot be struck twice" do
    duplicate = QuestionStrike.new(user: users(:buyer), question: questions(:spam_yellow), issued_by: users(:admin))

    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :question_id
  end

  test "issuing a strike emails the author" do
    strike = QuestionStrike.new(user: users(:confirmed), question: questions(:archived_yellow), issued_by: users(:admin))

    assert_enqueued_email_with QuestionMailer, :strike, args: [ strike ] do
      strike.save!
    end
  end

  test "strikes read in the order they were issued" do
    older = question_strikes(:spam_yellow_buyer)
    newer = QuestionStrike.create!(user: users(:buyer), question: questions(:answered_yellow), issued_by: users(:admin))

    assert_equal [ older, newer ], users(:buyer).question_strikes.chronological.to_a
  end

  test "deleting the author takes their strikes along" do
    user = users(:orderless)
    question = user.questions.create!(product: products(:yellow), body: "Vocês entregam em Manaus?")
    QuestionStrike.create!(user: user, question: question, issued_by: users(:admin))

    assert_difference -> { QuestionStrike.count }, -1 do
      user.destroy!
    end
  end
end
