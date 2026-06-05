class Question < ApplicationRecord
  belongs_to :product

  validates :body, presence: true
  validates :asker_name, presence: true
  validates :asker_email, presence: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }

  scope :published, -> { where(published: true) }
  scope :answered, -> { where(answered: true) }

  before_save :stamp_answered_at

  private

  def stamp_answered_at
    self.answered_at ||= Time.current if answered? && will_save_change_to_answered?
  end
end
