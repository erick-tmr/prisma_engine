class OptionType < ApplicationRecord
  has_many :option_values, dependent: :destroy
  has_many :product_option_types, dependent: :destroy
  has_many :products, through: :product_option_types

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  default_scope { order(:position) }
end
