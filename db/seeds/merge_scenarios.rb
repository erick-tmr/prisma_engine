raise "merge_scenarios seeds development data only" unless Rails.env.development?

module MergeScenarios
  EMAIL_DOMAIN = "qa-merge.test".freeze
  PASSWORD = "qa-merge-123".freeze
  PDF = "%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF".freeze

  SAO_PAULO = {
    receiver_name: "Cliente QA", zip: "01310100", street: "Avenida Paulista", number: "1000",
    complement: "Apto 42", neighborhood: "Bela Vista", city: "São Paulo", state: "SP"
  }.freeze
  RIO = {
    receiver_name: "Cliente QA", zip: "22041001", street: "Avenida Nossa Senhora de Copacabana", number: "500",
    complement: nil, neighborhood: "Copacabana", city: "Rio de Janeiro", state: "RJ"
  }.freeze

  HISTORY = {
    "awaiting_payment"    => [],
    "payment_confirmed"   => %w[payment_confirmed],
    "awaiting_components" => %w[payment_confirmed awaiting_components],
    "in_production"       => %w[payment_confirmed in_production],
    "production_issue"    => %w[payment_confirmed in_production production_issue],
    "label_issued"        => %w[payment_confirmed in_production label_issued],
    "shipped"             => %w[payment_confirmed in_production label_issued shipped],
    "delivered"           => %w[payment_confirmed in_production label_issued shipped delivered],
    "delivery_issue"      => %w[payment_confirmed in_production label_issued shipped delivery_issue],
    "returned"            => %w[payment_confirmed in_production label_issued shipped returned],
    "cancelled"           => %w[payment_confirmed cancelled]
  }.freeze

  LONG_NOTE = "Por favor embalar cada cartucho separado em plástico bolha, com a caixa original por fora " \
              "e o manual dentro do saco zip. Se possível enviar junto um adesivo da loja. Obrigado pelo " \
              "cuidado de sempre, é presente de aniversário e preciso que chegue em perfeito estado.".freeze

  module_function

  def users
    User.where("email LIKE ?", "%@#{EMAIL_DOMAIN}")
  end

  def reset!
    orders = Order.where(user_id: users.select(:id))
    shipments = Shipment.where(order_id: orders.select(:id))
    merges = OrderMerge.where(master_order_id: orders.select(:id)).or(OrderMerge.where(carrier_order_id: orders.select(:id)))
    ShipmentTrackingEvent.where(shipment_id: shipments.select(:id)).delete_all
    ShippingLabel.where(shipment_id: shipments.select(:id)).delete_all
    shipments.delete_all
    OrderItem.where(order_id: orders.select(:id)).delete_all
    OrderStatusChange.where(order_id: orders.select(:id)).delete_all
    merges.delete_all
    PaymentWebhookEvent.where(order_id: orders.select(:id)).delete_all
    orders.update_all(merged_into_id: nil)
    orders.delete_all
    users.find_each(&:destroy!)
  end

  def products
    @products ||= Product.where(published: true).order(:id).to_a.tap do |list|
      raise "Seed the catalog first (bin/rails db:seed)." if list.empty?
    end
  end

  def cpf(index)
    base = format("%09d", 314_159_000 + (index * 7_919))
    digits = base.chars.map(&:to_i)
    2.times do
      weights = (digits.size + 1).downto(2).to_a
      rest = digits.zip(weights).sum { |digit, weight| digit * weight } % 11
      digits << (rest < 2 ? 0 : 11 - rest)
    end
    digits.join
  end

  def client(code, title, index)
    User.create!(
      email: "#{code.downcase}@#{EMAIL_DOMAIN}", password: PASSWORD, password_confirmation: PASSWORD,
      full_name: "QA #{code} #{title}", cpf: cpf(index), phone: format("119%08d", 10_000_000 + index),
      confirmed_at: Time.current
    )
  end

  # :reek:LongParameterList
  def order(user, status:, age:, frete: 1_563, service: "mini_envios", weight: 150, address: SAO_PAULO,
            observation: nil, custom: false, label: nil, shipment: {})
    items = custom ? [ custom_item ] : [ catalog_item ]
    subtotal = items.sum { |item| item[:unit_price_cents] * item[:quantity] }
    placed = user.orders.create!(
      subtotal_cents: subtotal, total_cents: subtotal + frete, payment_method: "pix",
      observation: observation&.first(Order::OBSERVATION_LIMIT), order_items_attributes: items
    )
    placed.update_columns(status: status, created_at: age.ago, updated_at: age.ago)
    write_history(placed, status, age)
    ship = placed.create_shipment!(
      service: service, shipping_cents: frete, weight_grams: weight, delivery_business_days: 5,
      height_cm: Shipping::PACKAGE_DIMENSIONS[:altura_cm], width_cm: Shipping::PACKAGE_DIMENSIONS[:largura_cm],
      length_cm: Shipping::PACKAGE_DIMENSIONS[:comprimento_cm], receiver_cpf: user.cpf, **address, **shipment
    )
    attach_label(ship, label) if label
    placed
  end

  def catalog_item
    product = products.sample
    { product_id: product.id, name: product.title, unit_price_cents: product.price_cents, quantity: 1 }
  end

  def custom_item
    {
      name: "Pedido sob encomenda", unit_price_cents: 9_990, quantity: 1,
      requested_game: "Pokémon Crystal (tradução PT-BR)", request_notes: "Com save de fábrica limpo"
    }
  end

  def write_history(placed, status, age)
    placed.status_changes.update_all(created_at: age.ago, updated_at: age.ago)
    steps = HISTORY.fetch(status)
    rows = steps.each_with_index.map do |to, position|
      at = age.ago + (position + 1).hours
      { order_id: placed.id, from_status: position.zero? ? "awaiting_payment" : steps[position - 1],
        to_status: to, automatic: position.zero?, created_at: at, updated_at: at }
    end
    OrderStatusChange.insert_all(rows) if rows.any?
  end

  def attach_label(ship, spec)
    attrs = { state: spec.fetch(:state) }
    attrs.merge!(filename: "etiqueta-qa.pdf", pdf_base64: Base64.strict_encode64(PDF)) if spec[:state] == :ready
    attrs.merge!(error: "PPN-320 destinatário inválido (simulado)", errored_at: 5.minutes.ago) if spec[:error]
    attrs[:requesting_at] = 2.minutes.ago if spec[:state] == :requesting
    ship.create_shipping_label!(attrs)
  end

  def checkout_plan(carrier:, master:, absorbed:)
    OrderMerge.create!(
      carrier_order: carrier, master_order: master, absorbed_order_ids: absorbed.map(&:id),
      combined_weight_grams: 300, combined_service: "pac", combined_shipping_cents: 2_284,
      paid_fretes_cents: [ master, *absorbed ].sum { |order| order.shipment.shipping_cents }
    )
  end
end

S = MergeScenarios
S.reset! if ENV["RESET"] == "1"
if S.users.exists?
  abort "QA merge scenarios already exist. Run with RESET=1 to wipe and rebuild them " \
        "(merges consume orders, so rebuild before every test round)."
end

rows = []
index = 0
scenario = lambda do |code, title, &build|
  index += 1
  user = S.client(code, title, index)
  open_first = Array(build.call(user)).compact
  rows << [ code, title, user.email, open_first.map(&:number) ]
end

ready = { state: :ready }

scenario.call("S01", "basico") do |u|
  m = S.order(u, status: "payment_confirmed", age: 5.days)
  S.order(u, status: "payment_confirmed", age: 2.days)
  m
end

scenario.call("S02", "componentes puxa o mestre") do |u|
  m = S.order(u, status: "payment_confirmed", age: 5.days)
  S.order(u, status: "awaiting_components", age: 2.days)
  m
end

scenario.call("S03", "problema na producao herdado") do |u|
  m = S.order(u, status: "in_production", age: 5.days)
  S.order(u, status: "production_issue", age: 3.days)
  m
end

scenario.call("S04", "minimo estrito") do |u|
  m = S.order(u, status: "in_production", age: 5.days)
  S.order(u, status: "payment_confirmed", age: 1.day)
  m
end

scenario.call("S05", "quatro pedidos selecao parcial") do |u|
  m = S.order(u, status: "awaiting_components", age: 8.days)
  S.order(u, status: "payment_confirmed", age: 6.days)
  S.order(u, status: "in_production", age: 4.days)
  S.order(u, status: "production_issue", age: 2.days)
  m
end

scenario.call("S06", "mestre com etiqueta emitida") do |u|
  m = S.order(u, status: "label_issued", age: 6.days, label: ready)
  S.order(u, status: "payment_confirmed", age: 1.day)
  m
end

scenario.call("S07", "absorver pedido com etiqueta") do |u|
  m = S.order(u, status: "payment_confirmed", age: 6.days)
  S.order(u, status: "label_issued", age: 3.days, label: ready)
  m
end

scenario.call("S08", "etiqueta sendo emitida") do |u|
  m = S.order(u, status: "payment_confirmed", age: 6.days)
  busy = S.order(u, status: "in_production", age: 3.days, label: { state: :prepost_created })
  S.order(u, status: "in_production", age: 2.days, label: { state: :requested })
  [ m, busy ]
end

scenario.call("S09", "etiqueta com erro") do |u|
  m = S.order(u, status: "payment_confirmed", age: 6.days)
  S.order(u, status: "in_production", age: 3.days, label: { state: :prepost_confirmed, error: true })
  m
end

scenario.call("S10", "pre-postagem expirada") do |u|
  m = S.order(u, status: "label_issued", age: 20.days, label: ready,
                 shipment: { correios_status: 4, correios_status_label: "Expirado", correios_status_at: 1.day.ago })
  S.order(u, status: "payment_confirmed", age: 2.days)
  m
end

scenario.call("S11", "ja postado sync atrasado") do |u|
  m = S.order(u, status: "payment_confirmed", age: 6.days)
  posted = S.order(u, status: "label_issued", age: 3.days, label: ready, shipment: { posted_at: 2.hours.ago })
  [ m, posted ]
end

scenario.call("S12", "galeria de nao elegiveis") do |u|
  m = S.order(u, status: "payment_confirmed", age: 2.days)
  S.order(u, status: "awaiting_payment", age: 1.hour)
  S.order(u, status: "shipped", age: 10.days, shipment: { posted_at: 8.days.ago, tracking_state: :in_transit })
  S.order(u, status: "delivered", age: 30.days, shipment: { posted_at: 28.days.ago, delivered_at: 25.days.ago, tracking_state: :delivered })
  S.order(u, status: "delivery_issue", age: 15.days, shipment: { posted_at: 13.days.ago, tracking_state: :delivery_issue })
  S.order(u, status: "returned", age: 40.days, shipment: { posted_at: 38.days.ago, tracking_state: :returned })
  S.order(u, status: "cancelled", age: 12.days)
  m
end

scenario.call("S13", "mestre ja enviado") do |u|
  m = S.order(u, status: "shipped", age: 10.days, shipment: { posted_at: 8.days.ago, tracking_state: :in_transit })
  other = S.order(u, status: "payment_confirmed", age: 2.days)
  [ m, other ]
end

scenario.call("S14", "mestre cancelado") do |u|
  m = S.order(u, status: "cancelled", age: 10.days)
  S.order(u, status: "payment_confirmed", age: 2.days)
  m
end

scenario.call("S15", "upgrade mini envios para pac") do |u|
  m = S.order(u, status: "payment_confirmed", age: 5.days, weight: 250)
  S.order(u, status: "payment_confirmed", age: 2.days, weight: 250)
  m
end

scenario.call("S16", "frete do mestre maior que a cotacao") do |u|
  m = S.order(u, status: "payment_confirmed", age: 5.days, service: "sedex", frete: 8_000)
  S.order(u, status: "payment_confirmed", age: 2.days)
  m
end

scenario.call("S17", "mestre com frete gratis") do |u|
  m = S.order(u, status: "payment_confirmed", age: 5.days, frete: 0)
  S.order(u, status: "payment_confirmed", age: 2.days)
  m
end

scenario.call("S18", "endereco diferente") do |u|
  m = S.order(u, status: "payment_confirmed", age: 5.days)
  S.order(u, status: "payment_confirmed", age: 2.days, address: S::RIO)
  m
end

scenario.call("S19", "observacoes e limite de 1400") do |u|
  m = S.order(u, status: "payment_confirmed", age: 9.days, observation: "Nota do mestre: " + S::LONG_NOTE)
  (1..5).each { |n| S.order(u, status: "payment_confirmed", age: (9 - n).days, observation: "Nota #{n}: " + S::LONG_NOTE) }
  m
end

scenario.call("S20", "item sob encomenda") do |u|
  m = S.order(u, status: "payment_confirmed", age: 5.days)
  S.order(u, status: "awaiting_components", age: 2.days, custom: true)
  m
end

scenario.call("S21", "juncao de checkout aguardando pagamento") do |u|
  m = S.order(u, status: "payment_confirmed", age: 6.days)
  a = S.order(u, status: "awaiting_components", age: 4.days)
  free = S.order(u, status: "payment_confirmed", age: 2.days)
  carrier = S.order(u, status: "awaiting_payment", age: 1.hour, frete: 721)
  S.checkout_plan(carrier: carrier, master: m, absorbed: [ a ])
  [ free, m ]
end

scenario.call("S22", "carrier encalhado") do |u|
  master = S.order(u, status: "cancelled", age: 6.days)
  carrier = S.order(u, status: "payment_confirmed", age: 1.day, frete: 721)
  S.checkout_plan(carrier: carrier, master: master, absorbed: [])
  carrier
end

scenario.call("S23", "encadeamento") do |u|
  first = S.order(u, status: "payment_confirmed", age: 6.days)
  S.order(u, status: "payment_confirmed", age: 4.days)
  final = S.order(u, status: "payment_confirmed", age: 2.days)
  [ first, final ]
end

scenario.call("S24", "cliente com um pedido") do |u|
  S.order(u, status: "payment_confirmed", age: 2.days)
end

scenario.call("S25", "pagina velha") do |u|
  m = S.order(u, status: "payment_confirmed", age: 5.days)
  S.order(u, status: "payment_confirmed", age: 2.days)
  m
end

scenario.call("S26", "duas abas") do |u|
  m = S.order(u, status: "payment_confirmed", age: 5.days)
  S.order(u, status: "payment_confirmed", age: 2.days)
  m
end

scenario.call("S27", "adulteracao de numero") do |u|
  m = S.order(u, status: "payment_confirmed", age: 5.days)
  S.order(u, status: "payment_confirmed", age: 2.days)
  m
end

scenario.call("S28", "vitrine so oferece estados estritos") do |u|
  S.order(u, status: "payment_confirmed", age: 6.days)
  S.order(u, status: "in_production", age: 4.days)
  S.order(u, status: "label_issued", age: 2.days, label: ready)
  nil
end

scenario.call("S29", "correios fora do ar") do |u|
  m = S.order(u, status: "payment_confirmed", age: 5.days)
  S.order(u, status: "payment_confirmed", age: 2.days)
  m
end

host = ENV.fetch("QA_HOST") { "http://localhost:#{ENV.fetch('PORT', 3000)}" }
puts "Seeded #{rows.size} merge scenarios. Customer password for every QA client: #{S::PASSWORD}\n\n"
rows.each do |code, title, email, numbers|
  links = numbers.map { |number| "#{host}/admin/pedidos/#{number}" }
  puts format("%-4s %-40s %s", code, title, email)
  links.each { |link| puts "       #{link}" }
end
