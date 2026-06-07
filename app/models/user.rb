class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :confirmable,
         :recoverable, :rememberable, :validatable

  before_validation :normalize_cpf

  validates :full_name, presence: true
  validates :cpf, presence: true, uniqueness: true, cpf: true
  validates :phone, length: { maximum: 20 }, allow_blank: true

  def first_name
    full_name.to_s.split(/\s+/).first
  end

  private

  def normalize_cpf
    self.cpf = cpf.to_s.gsub(/\D/, "").presence
  end
end
