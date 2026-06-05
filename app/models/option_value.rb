class OptionValue < ApplicationRecord
  belongs_to :option_type
  has_many :variant_option_values, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :option_type_id }
  validates :price_contribution_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  default_scope { order(:position) }
end
