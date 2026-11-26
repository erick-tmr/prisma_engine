class StoreSetting < ApplicationRecord
  validates :handling_fee_cents,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :black_friday_ends_at,
            comparison: { greater_than: :black_friday_starts_at, message: :after_start },
            if: -> { black_friday_starts_at && black_friday_ends_at }

  def self.current
    first_or_create!
  end

  def black_friday?(at = Time.current)
    return false unless black_friday_starts_at && black_friday_starts_at <= at

    black_friday_ends_at.nil? || at < black_friday_ends_at
  end

  def black_friday_status(at = Time.current)
    return :disabled unless black_friday_starts_at
    return :scheduled if at < black_friday_starts_at
    return :ended unless black_friday?(at)

    black_friday_ends_at ? :active_until : :active
  end

  def turn_off_black_friday!
    update!(black_friday_starts_at: nil, black_friday_ends_at: nil)
  end
end
