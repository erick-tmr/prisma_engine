class CannedAnswer < ApplicationRecord
  LABEL_LENGTH = 32
  BODY_MINIMUM = 15

  normalizes :label, :body, with: ->(value) { value.strip }

  validates :label, presence: true, uniqueness: true, length: { maximum: LABEL_LENGTH, allow_blank: true }
  validates :body, presence: true, length: { minimum: BODY_MINIMUM, allow_blank: true }

  scope :ordered, -> { order(:created_at, :id) }
end
