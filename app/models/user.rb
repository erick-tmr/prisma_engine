class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :confirmable,
         :recoverable, :rememberable, :validatable, :lockable

  has_many :addresses, dependent: :destroy
  has_many :orders, dependent: :restrict_with_error
  has_many :questions, dependent: :destroy

  before_validation :normalize_cpf

  validates :full_name, presence: true
  validates :cpf, presence: true, uniqueness: true, cpf: true
  validates :phone, presence: true, length: { maximum: 20 }

  def first_name
    full_name.to_s.split(/\s+/).first
  end

  def default_address
    addresses.find_by(default: true)
  end

  private

  def normalize_cpf
    self.cpf = cpf.to_s.gsub(/\D/, "").presence
  end
end
