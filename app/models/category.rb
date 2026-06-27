class Category < ApplicationRecord
  MISCELLANEOUS_SLUG = "miscelanea".freeze

  has_many :products, dependent: :restrict_with_error

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  def miscellaneous?
    slug == MISCELLANEOUS_SLUG
  end
end
