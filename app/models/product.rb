class Product < ApplicationRecord
  include HasMoney
  extend FriendlyId
  friendly_id :name, use: [ :slugged, :history ]

  belongs_to :category

  has_many :variants, dependent: :destroy
  has_many :product_photos, -> { order(:position) }, dependent: :destroy
  has_many :questions, dependent: :destroy
  has_many :product_option_types, dependent: :destroy
  has_many :option_types, through: :product_option_types
  has_many :product_tags, dependent: :destroy
  has_many :tags, through: :product_tags

  validates :name, presence: true
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }

  scope :published, -> { where(published: true) }
  scope :for_category, ->(slug) { joins(:category).where(categories: { slug: slug }) }
  scope :featured, ->(limit = 8) {
    published.where.not("products.name LIKE ?", "- %").limit(limit)
  }

  money_attribute :price_cents, as: :price_formatted

  # --- Storefront read interface preserved from the former YAML PORO ---

  def title
    name
  end

  def category_label
    category&.name
  end

  def image
    photo = product_photos.first
    if photo&.image&.attached?
      Rails.application.routes.url_helpers.rails_blob_path(photo.image, only_path: true)
    else
      legacy_image_path
    end
  end

  def master_variant
    variants.find_by(is_master: true)
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
