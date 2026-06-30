class Recommendation < ApplicationRecord
  GRADIENTS = [
    "linear-gradient(135deg,#ff4e50,#f9d423)",
    "linear-gradient(135deg,#3a7bd5,#00d2ff)",
    "linear-gradient(135deg,#9b51e0,#ee0979)",
    "linear-gradient(135deg,#11998e,#38ef7d)"
  ].freeze

  validates :url, presence: true, uniqueness: true
  validate :url_must_be_http
  validates :position,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :active,           -> { where(active: true) }
  scope :in_display_order, -> { order(:position, :id) }

  def display_title
    title.presence || host
  end

  def letter_avatar_initial
    display_title[0].to_s.upcase
  end

  def avatar_gradient
    gradient.presence || GRADIENTS[position % GRADIENTS.size]
  end

  def host
    URI.parse(url.to_s).host.to_s
  end

  private

  def url_must_be_http
    uri = URI.parse(url.to_s)
    errors.add(:url, :invalid) unless uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    errors.add(:url, :invalid)
  end
end
