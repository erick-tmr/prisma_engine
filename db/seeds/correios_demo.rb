# Correios label-feedback demo data: idempotent, dev-only. Parks one order in
# every state the Correios column can render, so the column, the batch strip,
# the retry button and the live refresh can all be exercised without calling
# Correios. Keyed on external_id, so re-running never duplicates.
#
#   bin/rails runner 'load Rails.root.join("db/seeds/correios_demo.rb")'
#   MODE=step bin/rails runner 'load Rails.root.join("db/seeds/correios_demo.rb")'
#
# Re-running the default restores the whole spread, whatever state stepping left
# it in. There is no delete mode: Order#prevent_destroy keeps orders for history,
# so these eight stay in the dev database by design.
#
# `step` walks every demo label one stage forward. Run it while /admin is open
# to watch the cells swap in place: that is the auto-refresh under test.
#
# No label here is left in `requesting`, and any shipment carrying a tracking
# code is marked tracking_unavailable. Both are deliberate: with a Solid Queue
# worker running, Shipping::RecoverStuckLabelRequestsJob adopts a `requesting`
# label after 10 minutes and SyncPendingShipmentsJob polls anything in
# Shipment.awaiting_tracking, and either would reach the real Correios API with
# the credentials this machine already has.

DEMO_PREFIX = "correios-demo".freeze

# key, order status, label state, error message
DEMO_ORDERS = [
  [ "idle-a",    "in_production", nil,                nil ],
  [ "idle-b",    "in_production", nil,                nil ],
  [ "queued",    "in_production", :pending,           nil ],
  [ "created",   "in_production", :prepost_created,   nil ],
  [ "confirmed", "in_production", :prepost_confirmed, nil ],
  [ "requested", "in_production", :requested,         nil ],
  [ "failed",    "in_production", :prepost_confirmed, "PPN-320 CEP de destino inválido para o serviço contratado" ],
  [ "done",      "label_issued",  :ready,             nil ]
].freeze

NEXT_STATE = {
  "pending" => :prepost_created,
  "prepost_created" => :prepost_confirmed,
  "prepost_confirmed" => :requested,
  "requested" => :ready
}.freeze

def demo_orders
  Order.where("external_id LIKE ?", "#{DEMO_PREFIX}-%").includes(shipment: :shipping_label)
end

# Only clients Correios will actually accept: PrePostagemRequest splits the phone
# into dddCelular + celular and sends cpfCnpj and email verbatim, so a client
# missing any of them produces a pré-postagem the API rejects.
def correios_ready_clients
  User.clients.select do |user|
    user.phone.to_s.gsub(/\D/, "").length == 11 &&
      user.cpf.to_s.gsub(/\D/, "").length == 11 &&
      user.email.present?
  end
end

# Validates the payload the saga will really send, by building it with the same
# object CreatePrePostagemJob uses. Checking the builder's output rather than a
# copy of its rules means this cannot drift when the request shape changes.
def assert_correios_ready!(order)
  request = Shipping::PrePostagemRequest.from_shipment(order.shipment)
  recipient = request.recipient
  address = recipient[:endereco].to_h

  missing = []
  missing << "nome" if recipient[:nome].blank?
  missing << "dddCelular/celular" if recipient[:dddCelular].blank? || recipient[:celular].blank?
  missing << "email" if recipient[:email].blank?
  missing << "cpfCnpj(11)" unless recipient[:cpfCnpj].to_s.gsub(/\D/, "").length == 11
  missing << "cep(8)" unless address[:cep].to_s.gsub(/\D/, "").length == 8
  %i[logradouro numero bairro cidade uf].each { |key| missing << key if address[key].blank? }
  request.dimensions.each { |key, value| missing << key if value.to_i <= 0 }
  missing << "itens" if request.items.empty? || request.items.any? { |item| item[:conteudo].blank? }

  return if missing.empty?

  abort "#{order.number} is not Correios-ready, missing: #{missing.join(', ')}"
end

def sample_label_pdf
  path = Rails.root.join("db/seeds/correios_label_sample.pdf")
  File.exist?(path) ? Base64.strict_encode64(File.binread(path)) : Base64.strict_encode64("%PDF-1.4 demo")
end

def demo_tracking_code(order)
  "PG#{format('%09d', order.id)}BR"
end

def step_demo!
  moved = demo_orders.filter_map do |order|
    label = order.shipment&.shipping_label
    target = label && NEXT_STATE[label.state]
    advance_label(order, label, target) if target
  end

  puts moved.any? ? "Advanced:\n  #{moved.join("\n  ")}" : "Nothing left to advance. Re-run without MODE to restore the spread."
end

def advance_label(order, label, target)
  case target
  when :requested
    label.update!(state: :requested, recibo_id: "demo-recibo-#{order.number}", error: nil, errored_at: nil)
  when :ready
    label.update!(state: :ready, filename: "etiqueta-#{order.number}.pdf", pdf_base64: sample_label_pdf,
                  error: nil, errored_at: nil)
    order.shipment.update!(tracking_code: demo_tracking_code(order), tracking_state: :unavailable)
    # The real transition, so the status-change row and the customer e-mail fire
    # exactly as in production. Dev captures mail in letter_opener_web.
    order.advance_to_label_issued!(automatic: true)
  else
    label.update!(state: target, error: nil, errored_at: nil)
  end

  "#{order.number}  #{label.reload.state}"
end

def ensure_order(key, status, index, user)
  order = Order.find_or_initialize_by(external_id: "#{DEMO_PREFIX}-#{key}")
  if order.new_record?
    placed_at = Time.current - index.minutes
    order.assign_attributes(
      user: user, number: "PG-#{Date.current.strftime('%Y%m%d')}9#{format('%03d', index)}",
      subtotal_cents: 19_000, total_cents: 21_990, payment_method: "pix",
      created_at: placed_at, updated_at: placed_at
    )
    order.order_items.build(name: "Cartucho de teste Correios (#{key})", unit_price_cents: 19_000, quantity: 1)
  end
  order.status = status
  order.save!
  ensure_shipment(order, index, user)
  order
end

def ensure_shipment(order, index, user)
  shipment = order.shipment || order.build_shipment
  shipment.assign_attributes(
    service: "pac", shipping_cents: 2_990,
    weight_grams: 60 + Shipping::PACKAGE_OVERHEAD_GRAMS,
    height_cm: Shipping::PACKAGE_DIMENSIONS.fetch(:altura_cm),
    width_cm: Shipping::PACKAGE_DIMENSIONS.fetch(:largura_cm),
    length_cm: Shipping::PACKAGE_DIMENSIONS.fetch(:comprimento_cm),
    receiver_name: user.full_name, receiver_cpf: user.cpf,
    zip: "01310100", street: "Avenida Paulista", number: format("%03d", 900 + index),
    neighborhood: "Bela Vista", city: "São Paulo", state: "SP",
    receiver_obs: "Entregar na portaria, falar com o zelador."
  )
  shipment.save!
end

def park_label(order, state, error)
  shipment = order.shipment
  # A shipment with a pre_post_id has a real object at Correios and, most likely,
  # a live saga. Faking its state destroys the label, which makes the next
  # EmitLabel.resume restart the chain and buy a second real pré-postagem, and
  # nulls the tracking code, which strands ConfirmPrePostagem forever.
  return :skipped_live_saga if shipment.pre_post_id.present?

  shipment.shipping_label&.destroy
  shipment.reload
  return shipment.update!(tracking_code: nil, tracking_state: :pending) if state.nil?

  label = shipment.create_shipping_label!(state: state)
  label.update!(recibo_id: "demo-recibo-#{order.number}") if %i[requested ready].include?(state)
  label.update!(filename: "etiqueta-#{order.number}.pdf", pdf_base64: sample_label_pdf) if state == :ready
  label.record_error!(error) if error
  ready_tracking(shipment, order, state)
end

def ready_tracking(shipment, order, state)
  return shipment.update!(tracking_code: nil, tracking_state: :pending) unless state == :ready

  shipment.update!(tracking_code: demo_tracking_code(order), tracking_state: :unavailable)
end

# One order mid-return, so the awaiting_return / returning / returned e-mail
# previews resolve and the backoffice renders the inbound leg. The inbound
# shipment is marked tracking_unavailable for the same reason as the outbound
# ones above: SyncPendingShipmentsJob would otherwise reach the real Correios.
def ensure_return_demo(user, index)
  order = ensure_order("returning", "returning", index, user)
  outbound = order.shipment
  shipment = order.return_shipment ||
             Shipment.create!(order: order, direction: :inbound, service: Shipping::DEFAULT_RETURN_SERVICE,
                              **outbound.slice(*Shipping::StartReturn::CLONED).symbolize_keys)
  shipment.update!(tracking_code: "PR#{format('%09d', order.id)}BR", tracking_state: :unavailable)
  label = shipment.shipping_label || shipment.create_shipping_label!
  label.update!(state: :ready, filename: "devolucao-#{order.number}.pdf", pdf_base64: sample_label_pdf)
  order
end

if ENV["MODE"] == "step"
  step_demo!
else
  clients = correios_ready_clients
  abort "No client has a usable phone, CPF and e-mail. Run bin/rails db:seed first." if clients.empty?

  rows = DEMO_ORDERS.each_with_index.map do |(key, status, state, error), index|
    order = ensure_order(key, status, index + 1, clients[index % clients.size])
    skipped = park_label(order, state, error) == :skipped_live_saga
    assert_correios_ready!(order.reload)
    note = skipped ? "  (left alone: live pré-postagem #{order.shipment.pre_post_id})" : ""
    "#{order.number}  #{status.ljust(14)} #{Admin::LabelFeedback.new(order).state}#{note}"
  end

  returning = ensure_return_demo(clients.first, DEMO_ORDERS.size + 1)
  rows << "#{returning.number}  #{'returning'.ljust(14)} devolução pronta para baixar"

  puts "Correios demo orders (newest first in /admin):"
  puts rows.map { |line| "  #{line}" }
  puts "\nAll #{DEMO_ORDERS.size} validated against Shipping::PrePostagemRequest: safe to emit for real."
  puts "MODE=step advances them one stage. Re-run without MODE to restore this spread."
end
