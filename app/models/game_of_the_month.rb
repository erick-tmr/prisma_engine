class GameOfTheMonth < ApplicationRecord
  has_many :game_of_the_month_products, dependent: :destroy
  has_many :products, through: :game_of_the_month_products
  has_many :brindes, through: :game_of_the_month_products

  has_many :published_picks,
           -> { joins(:product).merge(Product.published).in_display_order },
           class_name: "GameOfTheMonthProduct",
           inverse_of: :game_of_the_month
  has_many :published_products,
           -> { published },
           through: :game_of_the_month_products,
           source: :product

  before_validation :apply_default_publish_at

  validates :year,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 2000 }
  validates :month,
            presence: true,
            numericality: { only_integer: true, in: 1..12 }
  validates :year, uniqueness: { scope: :month }
  validates :publish_at, presence: true

  scope :for_month, ->(year, month) { where(year: year, month: month) }
  scope :current,   -> { for_month(Time.current.year, Time.current.month) }
  scope :due_for_publishing, -> { where(published_at: nil).where(publish_at: ..Time.current) }

  def self.current_product_ids
    current.first&.published_products&.ids || []
  end

  def self.feature_first(products, featured_ids = current_product_ids)
    featured, rest = products.order(:id).partition { |product| featured_ids.include?(product.id) }
    featured + rest
  end

  private

  def apply_default_publish_at
    return if publish_at.present?
    return unless year.to_i.positive? && (1..12).cover?(month.to_i)

    self.publish_at = Time.zone.local(year, month, 1)
  end
end
