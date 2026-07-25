class Product < ApplicationRecord
  extend FriendlyId
  friendly_id :name, use: [ :slugged, :history ]

  belongs_to :category

  has_one :custom_order_form, dependent: :destroy

  has_many :product_options, dependent: :destroy
  has_many :product_photos, dependent: :destroy
  has_many :questions, dependent: :destroy
  has_many :product_tags, dependent: :destroy
  has_many :tags, through: :product_tags
  has_many :game_of_the_month_products, dependent: :destroy

  validates :name, presence: true
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :weight_grams,
            presence: true,
            numericality: { only_integer: true, greater_than: 0 }

  scope :published, -> { where(published: true) }
  scope :for_category, ->(slug) { joins(:category).where(categories: { slug: slug }) }
  scope :featured, ->(limit = 8) {
    published.where.not("products.name LIKE ?", "- %").limit(limit)
  }
  scope :meta_stale, -> {
    where("catalog_synced_at IS NULL OR products.updated_at > catalog_synced_at")
      .where("(published = TRUE AND price_cents > 0) OR catalog_synced_at IS NOT NULL")
  }

  def price_formatted
    price_cents.to_i.zero? ? "Sob consulta" : HasMoney.format(price_cents)
  end

  def custom_order_text
    custom_order_form || CustomOrderForm.new
  end

  def title
    name
  end

  def syncable_to_meta?
    published? && price_cents.positive? && usable_public_image?
  end

  def usable_public_image?
    product_photos.any? { |photo| photo.image.attached? }
  end

  def category_label
    category&.name
  end

  def image
    @image ||= begin
      photo = product_photos.min_by(&:position)
      if photo&.image&.attached?
        Storefront::ImageSource.call(photo.image)
      else
        legacy_image_path
      end
    end
  end

  def normalize_friendly_id(value)
    CGI.unescapeHTML(value.to_s)
       .gsub(/[^\p{Latin}\p{Digit}\s-]/, "")
       .parameterize
  end
end
