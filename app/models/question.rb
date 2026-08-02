class Question < ApplicationRecord
  STATUSES = %w[awaiting_answer draft answered spam archived].freeze
  VISIBLE_STATUSES = %w[awaiting_answer draft answered].freeze
  PENDING_STATUSES = %w[awaiting_answer draft].freeze
  BODY_LENGTH = 10..500

  belongs_to :product
  belongs_to :user
  has_one :question_strike, dependent: :destroy

  enum :status, STATUSES.index_with(&:itself), default: "awaiting_answer", validate: true

  normalizes :body, with: ->(value) { value.strip }

  validates :body, presence: true, length: { in: BODY_LENGTH, allow_blank: true }
  validates :answer_body, presence: true, if: :written?

  scope :visible, -> { where(status: VISIBLE_STATUSES) }
  scope :pending, -> { where(status: PENDING_STATUSES) }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  scope :oldest_first, -> { order(created_at: :asc, id: :asc) }

  before_save :stamp_answered_at
  after_update_commit :deliver_answer_email

  def written?
    draft? || answered?
  end

  def visible?
    VISIBLE_STATUSES.include?(status)
  end

  private

  def stamp_answered_at
    self.answered_at ||= Time.current if answered? && will_save_change_to_status?
  end

  def deliver_answer_email
    return unless answered? && saved_change_to_status?

    QuestionMailer.answered(self).deliver_later
  end
end
