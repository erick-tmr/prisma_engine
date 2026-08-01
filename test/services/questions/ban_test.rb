require "test_helper"

module Questions
  class BanTest < ActiveSupport::TestCase
    def strike(user, question, at:)
      QuestionStrike.create!(user: user, question: question, issued_by: users(:admin), created_at: at)
    end

    test "a customer who never spammed can ask freely" do
      ban = Ban.new(users(:orderless))

      assert_equal 0, ban.strikes
      assert_not_predicate ban, :active?
      assert_not_predicate ban, :permanent?
      assert_nil ban.expires_at
    end

    test "the first strike closes questions for a week" do
      ban = Ban.new(users(:buyer))

      assert_equal 1, ban.strikes
      assert_predicate ban, :active?
      assert_not_predicate ban, :permanent?
      assert_equal "first", ban.penalty
      assert_in_delta question_strikes(:spam_yellow_buyer).created_at + 1.week, ban.expires_at, 1.minute
    end

    test "a week after the only strike the customer can ask again" do
      question_strikes(:spam_yellow_buyer).update!(created_at: 8.days.ago)

      assert_not_predicate Ban.new(users(:buyer)), :active?
    end

    test "the second strike closes questions for a month" do
      newest = 2.days.ago
      strike(users(:buyer), questions(:answered_yellow), at: newest)
      ban = Ban.new(users(:buyer))

      assert_equal 2, ban.strikes
      assert_predicate ban, :active?
      assert_equal "second", ban.penalty
      assert_in_delta newest + 1.month, ban.expires_at, 1.minute
    end

    test "a month after the second strike the customer can ask again" do
      question_strikes(:spam_yellow_buyer).update!(created_at: 60.days.ago)
      strike(users(:buyer), questions(:answered_yellow), at: 40.days.ago)

      assert_not_predicate Ban.new(users(:buyer)), :active?
    end

    test "the third strike closes questions for good" do
      strike(users(:buyer), questions(:answered_yellow), at: 2.years.ago)
      strike(users(:buyer), questions(:awaiting_yellow), at: 1.year.ago)
      ban = Ban.new(users(:buyer))

      assert_equal 3, ban.strikes
      assert_predicate ban, :permanent?
      assert_predicate ban, :active?
      assert_equal "permanent", ban.penalty
      assert_nil ban.expires_at
    end

    test "the next penalty escalates from what the account already carries" do
      assert_equal "first", Ban.new(users(:orderless)).next_penalty
      assert_equal "second", Ban.new(users(:buyer)).next_penalty

      strike(users(:buyer), questions(:answered_yellow), at: 1.day.ago)

      assert_equal "permanent", Ban.new(users(:buyer)).next_penalty
    end
  end
end
