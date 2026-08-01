class QuestionStrike < ApplicationRecord
  belongs_to :user
  belongs_to :question
  belongs_to :issued_by, class_name: "User"

  validates :question_id, uniqueness: true

  scope :chronological, -> { order(:created_at, :id) }

  after_create_commit :deliver_strike_email

  private

  def deliver_strike_email
    QuestionMailer.strike(self).deliver_later
  end
end
