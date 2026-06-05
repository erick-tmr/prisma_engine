class ProductPhoto < ApplicationRecord
  belongs_to :product
  belongs_to :variant, optional: true

  has_one_attached :image

  validate :variant_belongs_to_product

  private

  def variant_belongs_to_product
    return if variant.nil? || variant.product_id == product_id

    errors.add(:variant, "must belong to the same product")
  end
end
