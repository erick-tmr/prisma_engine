class Question < ApplicationRecord
  STATUSES = %w[awaiting_answer answered spam archived].freeze
  VISIBLE_STATUSES = %w[awaiting_answer answered].freeze
  BODY_LENGTH = 10..500

  belongs_to :product
  belongs_to :user

  enum :status, STATUSES.index_with(&:itself), default: "awaiting_answer", validate: true

  normalizes :body, with: ->(value) { value.strip }

  validates :body, presence: true, length: { in: BODY_LENGTH, allow_blank: true }
  validates :answer_body, presence: true, if: :answered?

  scope :visible, -> { where(status: VISIBLE_STATUSES) }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  before_save :stamp_answered_at

  private

  def stamp_answered_at
    self.answered_at ||= Time.current if answered? && will_save_change_to_status?
  end
end
