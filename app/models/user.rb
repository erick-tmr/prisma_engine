class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :confirmable,
         :recoverable, :rememberable, :validatable, :lockable

  has_many :addresses, dependent: :destroy
  has_many :orders, dependent: :restrict_with_error
  has_many :questions, dependent: :destroy
  has_many :question_strikes, dependent: :destroy

  scope :clients, -> { where(admin: false) }
  scope :expired_signups, -> { where(confirmed_at: nil, confirmation_sent_at: ...confirm_within.ago) }

  before_validation :normalize_cpf
  before_validation :normalize_phone
  before_create :release_expired_cpf_holder

  validates :full_name, presence: true
  validates :cpf, presence: true, cpf: true
  validates :cpf, uniqueness: { conditions: -> { where.not(id: expired_signups.select(:id)) } }, on: :create
  validates :cpf, uniqueness: true, on: :update
  validates :phone, presence: true, length: { maximum: 20 }, phone: true

  def self.normalized_cpf(value)
    value.to_s.gsub(/\D/, "").presence
  end

  def self.pending_signup(cpf:, password:)
    clients.where(cpf: normalized_cpf(cpf), confirmed_at: nil).detect { |holder| holder.valid_password?(password) }
  end

  def first_name
    full_name.to_s.split(/\s+/).first
  end

  def default_address
    addresses.find_by(default: true)
  end

  def update_contact(attributes)
    skip_reconfirmation!
    assign_attributes(attributes)
    vouch_for_new_email if email.to_s.strip.downcase != email_in_database
    saved = save
    announce_email_change if saved && saved_change_to_email?
    saved
  end

  def correct_signup_email(new_email)
    return false if confirmed?

    skip_reconfirmation!
    skip_email_changed_notification!
    self.email = new_email
    saved = save
    reissue_confirmation if saved && saved_change_to_email?
    saved
  end

  private

  def reissue_confirmation
    self.confirmation_token = nil
    send_confirmation_instructions
  end

  def release_expired_cpf_holder
    User.expired_signups.where(cpf:).find_each(&:destroy!)
  end

  def vouch_for_new_email
    self.unconfirmed_email = nil
    self.confirmation_token = nil
    self.confirmed_at ||= Time.current
  end

  def announce_email_change
    ContactChangeMailer.previous_address(self, email_before_last_save).deliver_later
    ContactChangeMailer.new_address(self).deliver_later
  end

  def normalize_cpf
    self.cpf = self.class.normalized_cpf(cpf)
  end

  def normalize_phone
    digits = Phones.national(phone)
    self.phone = digits ? PhoneFormat.call(digits) : phone.presence
  end
end
