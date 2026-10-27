class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :confirmable,
         :recoverable, :rememberable, :validatable, :lockable

  has_many :addresses, dependent: :destroy
  has_many :orders, dependent: :restrict_with_error
  has_many :questions, dependent: :destroy
  has_many :question_strikes, dependent: :destroy

  scope :clients, -> { where(admin: false) }

  before_validation :normalize_cpf
  before_validation :normalize_phone

  validates :full_name, presence: true
  validates :cpf, presence: true, uniqueness: true, cpf: true
  validates :phone, presence: true, length: { maximum: 20 }, phone: true

  def first_name
    full_name.to_s.split(/\s+/).first
  end

  def default_address
    addresses.find_by(default: true)
  end

  def update_contact(attributes)
    skip_reconfirmation!
    assign_attributes(attributes)
    self.unconfirmed_email = nil if email.to_s.strip.downcase != email_in_database
    saved = save
    announce_email_change if saved && saved_change_to_email?
    saved
  end

  private

  def announce_email_change
    ContactChangeMailer.previous_address(self, email_before_last_save).deliver_later
    ContactChangeMailer.new_address(self).deliver_later
  end

  def normalize_cpf
    self.cpf = cpf.to_s.gsub(/\D/, "").presence
  end

  def normalize_phone
    digits = Phones.national(phone)
    self.phone = digits ? PhoneFormat.call(digits) : phone.presence
  end
end
