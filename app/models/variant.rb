class Variant < ApplicationRecord
  include HasMoney

  belongs_to :product
  has_many :variant_option_values, dependent: :destroy
  has_many :option_values, through: :variant_option_values
  has_many :product_photos, dependent: :nullify

  validates :sku, presence: true, uniqueness: true
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
  validate :only_one_master_per_product

  scope :available, -> { where(available: true) }

  money_attribute :price_cents, as: :price_formatted

  # Absolute SKU price plus the reusable per-option contributions
  # (e.g. "Com caixa" adds, "Idioma" adds nothing).
  def computed_price_cents
    price_cents + option_values.sum(:price_contribution_cents)
  end

  private

  def only_one_master_per_product
    return unless is_master? && product

    clash = product.variants.where(is_master: true).where.not(id: id).exists?
    errors.add(:is_master, "product already has a master variant") if clash
  end
end
