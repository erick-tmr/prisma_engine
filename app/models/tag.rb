class Tag < ApplicationRecord
  extend FriendlyId
  friendly_id :name, use: :slugged

  has_many :product_tags, dependent: :destroy
  has_many :products, through: :product_tags

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
end
