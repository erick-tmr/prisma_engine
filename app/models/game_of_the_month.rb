class GameOfTheMonth < ApplicationRecord
  has_many :game_of_the_month_products, dependent: :destroy
  has_many :products, through: :game_of_the_month_products
  has_many :brindes, through: :game_of_the_month_products

  validates :year,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 2000 }
  validates :month,
            presence: true,
            numericality: { only_integer: true, in: 1..12 }
  validates :year, uniqueness: { scope: :month }

  scope :for_month, ->(year, month) { where(year: year, month: month) }
  scope :current,   -> { for_month(Time.current.year, Time.current.month) }

  def self.current_product_ids
    current.first&.product_ids || []
  end

  def self.feature_first(products, featured_ids = current_product_ids)
    featured, rest = products.order(:id).partition { |product| featured_ids.include?(product.id) }
    featured + rest
  end
end
