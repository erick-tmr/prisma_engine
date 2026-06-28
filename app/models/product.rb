class Product < ApplicationRecord
  extend FriendlyId
  friendly_id :name, use: [ :slugged, :history ]

  belongs_to :category

  has_many :product_options, dependent: :destroy
  has_many :product_photos, dependent: :destroy
  has_many :questions, dependent: :destroy
  has_many :product_tags, dependent: :destroy
  has_many :tags, through: :product_tags

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

  # An unpriced product means "ask for the price" — not "R$ 0.00".
  def price_formatted
    price_cents.to_i.zero? ? "Sob consulta" : HasMoney.format(price_cents)
  end

  # --- Storefront read interface preserved from the former YAML PORO ---

  def title
    name
  end

  def game?
    !category.miscellaneous?
  end

  def category_label
    category&.name
  end

  def image
    photo = product_photos.in_display_order.first
    if photo&.image&.attached?
      Storefront::ImageSource.call(photo.image)
    else
      legacy_image_path
    end
  end

  # Titles carry HTML entities (&#039;, &amp;) and emoji; unescape and strip
  # anything non-alphanumeric before parameterize so generated slugs stay clean
  # (e.g. "Kirby&#039;s Dream Land" -> "kirbys-dream-land"). friendly_id calls
  # this publicly, so it must not be private.
  def normalize_friendly_id(value)
    CGI.unescapeHTML(value.to_s)
       .gsub(/[^\p{Latin}\p{Digit}\s-]/, "")
       .parameterize
  end
end
