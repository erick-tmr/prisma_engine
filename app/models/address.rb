class Address < ApplicationRecord
  # Mirrors the Correios prepostagem destinatario.endereco block (see
  # app/services/shipping/pre_postagem_request.rb). The address book feeds
  # the future Shipping::CreatePrePostagem flow with zero translation.
  UF_LIST = %w[
    AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO
  ].freeze

  belongs_to :user

  before_validation :normalize_zip
  before_create :mark_default_when_first

  validates :zip, presence: true, format: { with: /\A\d{8}\z/, message: :invalid_format }
  validates :street, :number, :neighborhood, :city, presence: true
  validates :state, presence: true, inclusion: { in: UF_LIST, message: :not_in_list }

  scope :default_first, -> { order(default: :desc, id: :asc) }

  # Transactional: flips every other address for this user to non-default, then
  # marks this one as default. Idempotent if this address is already default.
  def mark_default!
    transaction do
      user.addresses.where.not(id: id).update_all(default: false)
      update!(default: true)
    end
  end

  private

  def normalize_zip
    self.zip = zip.to_s.gsub(/\D/, "").presence
  end

  def mark_default_when_first
    self.default = true unless user.addresses.exists?
  end
end
