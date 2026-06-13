class Order < ApplicationRecord
  # Raised when a caller asks for a lifecycle move the graph doesn't allow.
  InvalidTransition = Class.new(StandardError)
  # Raised only if every random number draw collides — astronomically unlikely at
  # this volume, surfaced rather than silently retried forever or saving a dup.
  UnallocatableNumber = Class.new(StandardError)

  # How many random draws to try before giving up on a free number.
  NUMBER_ATTEMPTS = 10

  belongs_to :user
  has_many :order_items, dependent: :destroy
  # Built atomically with the order in Checkout::PlaceOrder (one snapshot, one save).
  accepts_nested_attributes_for :order_items

  # Customer-facing lifecycle (docs/architecture.md § 4): six states plus the two
  # branch states. String-backed so the stored value reads the same as the
  # account.orders.states.<status> locale keys; mirrors Shipment's enum lifecycle
  # (no state-machine gem — the graph below is plain data).
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

  # The lifecycle graph (arch § 4). Non-linear — two branch points: after
  # pagamento_confirmado (→ em_producao | aguardando_componentes) and during
  # em_producao (→ etiqueta_emitida | problema_na_producao). Only confirm_payment
  # is wired today; the remaining edges are exercised by fulfillment features as
  # they land. Recovery edges (problema_na_producao → em_producao) are operator moves.
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

  # Cancellation window closes when production starts (arch § 0.1). Matches
  # Account::MockOrder#cancellable? so swapping mocks for this model is behaviour-preserving.
  CANCELLABLE_STATUSES = %w[aguardando_pagamento pagamento_confirmado].freeze

  validates :number, presence: true, uniqueness: true
  validates :subtotal_cents, :shipping_cents, :total_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :shipping_service, inclusion: { in: Shipping::SERVICES.keys.map(&:to_s) }

  before_validation :assign_number, on: :create

  # placed_at / shipping_address expose the Account::MockOrder shape so the Pedidos
  # views can render a real Order unchanged once they're swapped off the mocks.
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

  # Canonical lifecycle mutation: only edges declared in TRANSITIONS are allowed.
  # (Rails' generated enum bang setters bypass this — go through here.)
  def transition_to!(next_status)
    target = next_status.to_s
    raise InvalidTransition, "#{status} → #{target}" unless TRANSITIONS.fetch(status).include?(target)

    update!(status: target)
  end

  def confirm_payment!
    transition_to!("pagamento_confirmado")
  end

  private

  # PG-YYYYMMDD#### — "PG", the order date, and four random digits. Easy to read
  # aloud and to eyeball, and four digits is plenty of orders per day at this
  # volume. Fixtures set `number` directly and never reach this.
  def assign_number
    return if number.present?

    self.number = generate_unique_number
  end

  # Regenerated on the rare collision; the unique index is the final backstop.
  def generate_unique_number
    NUMBER_ATTEMPTS.times do
      candidate = "PG-#{Time.current.strftime('%Y%m%d')}#{format('%04d', rand(10_000))}"
      return candidate unless self.class.exists?(number: candidate)
    end
    raise UnallocatableNumber
  end
end
