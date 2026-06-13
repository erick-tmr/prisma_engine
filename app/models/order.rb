class Order < ApplicationRecord
  InvalidTransition = Class.new(StandardError)
  UnallocatableNumber = Class.new(StandardError)

  NUMBER_ATTEMPTS = 10

  belongs_to :user
  has_many :order_items, dependent: :destroy
  accepts_nested_attributes_for :order_items

  STATUSES = %w[
    aguardando_pagamento
    pagamento_confirmado
    aguardando_componentes
    em_producao
    problema_na_producao
    etiqueta_emitida
    enviado
    entregue
  ].freeze

  enum :status, STATUSES.index_with(&:itself), default: "aguardando_pagamento", validate: true

  TRANSITIONS = {
    "aguardando_pagamento"   => %w[pagamento_confirmado],
    "pagamento_confirmado"   => %w[aguardando_componentes em_producao],
    "aguardando_componentes" => %w[em_producao],
    "em_producao"            => %w[etiqueta_emitida problema_na_producao],
    "problema_na_producao"   => %w[em_producao],
    "etiqueta_emitida"       => %w[enviado],
    "enviado"                => %w[entregue],
    "entregue"               => []
  }.freeze

  CANCELLABLE_STATUSES = %w[aguardando_pagamento pagamento_confirmado].freeze

  validates :number, presence: true, uniqueness: true
  validates :subtotal_cents, :shipping_cents, :total_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :shipping_service, inclusion: { in: Shipping::SERVICES.keys.map(&:to_s) }

  before_validation :assign_number, on: :create

  def placed_at
    created_at
  end

  def shipping_address
    {
      recipient: ship_receiver_name, cpf: ship_receiver_cpf,
      street: ship_street, number: ship_number, complement: ship_complement,
      neighborhood: ship_neighborhood, city: ship_city, state: ship_state, zip: ship_zip
    }
  end

  def cancellable?
    CANCELLABLE_STATUSES.include?(status)
  end

  def transition_to!(next_status)
    target = next_status.to_s
    raise InvalidTransition, "#{status} → #{target}" unless TRANSITIONS.fetch(status).include?(target)

    update!(status: target)
  end

  def confirm_payment!
    transition_to!("pagamento_confirmado")
  end

  private

  def assign_number
    return if number.present?

    self.number = generate_unique_number
  end

  def generate_unique_number
    NUMBER_ATTEMPTS.times do
      candidate = "PG-#{Time.current.strftime('%Y%m%d')}#{format('%04d', rand(10_000))}"
      return candidate unless self.class.exists?(number: candidate)
    end
    raise UnallocatableNumber
  end
end
