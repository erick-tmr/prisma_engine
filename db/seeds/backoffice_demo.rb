# Backoffice demo data — idempotent. Populates the admin dashboard locally with a
# realistic spread of customers (across situações) and orders (across every
# Order::STATUSES value and a range of dates). Keyed on stable identifiers
# (customer e-mail, order external_id) so re-running never duplicates. Test
# fixtures stay separate — this is dev-only seed data.

# CPF check digits via the official mod-11 algorithm (mirrors CpfValidator), so
# every generated customer passes `cpf: true` validation.
def cpf_check_digit(slice, start_weight)
  sum = slice.chars.each_with_index.sum { |char, index| char.to_i * (start_weight - index) }
  remainder = (sum * 10) % 11
  remainder == 10 ? 0 : remainder
end

def valid_cpf(base9)
  d10 = cpf_check_digit(base9, 10)
  d11 = cpf_check_digit(base9 + d10.to_s, 11)
  "#{base9}#{d10}#{d11}"
end

# name, city, UF, situação (active / pending / locked)
customers = [
  [ "Ana Beatriz Cardoso", "São Paulo",       "SP", :active ],
  [ "Bruno Tanaka",        "Campinas",        "SP", :active ],
  [ "Carla Menezes",       "Rio de Janeiro",  "RJ", :active ],
  [ "Diego Fontes",        "Belo Horizonte",  "MG", :pending ],
  [ "Eduarda Lima",        "Curitiba",        "PR", :active ],
  [ "Felipe Andrade",      "Porto Alegre",    "RS", :active ],
  [ "Gabriela Rocha",      "Fortaleza",       "CE", :locked ],
  [ "Henrique Sales",      "Santo André",     "SP", :active ],
  [ "Isabela Cunha",       "Goiânia",         "GO", :active ],
  [ "João Pedro Nunes",    "Joinville",       "SC", :active ],
  [ "Larissa Vieira",      "Salvador",        "BA", :pending ],
  [ "Marcos Aurélio",      "Ribeirão Preto",  "SP", :active ],
  [ "Natália Prado",       "Florianópolis",   "SC", :active ],
  [ "Otávio Bittencourt",  "Recife",          "PE", :active ]
]

customer_records = customers.each_with_index.map do |(name, city, uf, situation), index|
  email = "#{name.parameterize}@prismagames.dev"
  user = User.find_or_initialize_by(email: email)
  if user.new_record?
    user.skip_confirmation_notification!
    user.assign_attributes(
      full_name: name,
      cpf: valid_cpf(format("%09d", 200_000_001 + index * 37)),
      phone: format("11%09d", 900_000_000 + index),
      password: "cliente123", password_confirmation: "cliente123"
    )
    user.confirmed_at = Time.current unless situation == :pending
    user.confirmation_sent_at = Time.current if situation == :pending
    user.locked_at = Time.current if situation == :locked
    user.save!
    user.addresses.create!(
      receiver_name: name, receiver_cpf: user.cpf, zip: "01310100",
      street: "Avenida Paulista", number: format("%03d", 100 + index),
      neighborhood: "Centro", city: city, state: uf
    )
  end
  [ user, city, uf ]
end

# customer index, status, days ago, total (cents), item quantity
orders = [
  [ 2,  "awaiting_payment",   1,  48_900, 2 ],
  [ 0,  "payment_confirmed",  2, 127_400, 3 ],
  [ 8,  "in_production",      4,  32_900, 1 ],
  [ 4,  "in_production",      6,  89_800, 2 ],
  [ 7,  "awaiting_components", 9, 215_600, 4 ],
  [ 1,  "label_issued",      13,  54_900, 1 ],
  [ 12, "shipped",           16,  73_200, 2 ],
  [ 13, "shipped",           19,  41_900, 1 ],
  [ 5,  "delivered",         22, 158_300, 3 ],
  [ 8,  "delivered",         26,  29_900, 1 ],
  [ 9,  "delivered",         31,  96_700, 2 ],
  [ 2,  "production_issue",  35,  62_400, 2 ],
  [ 6,  "cancelled",         40,  38_900, 1 ],
  [ 0,  "delivered",         48, 112_900, 3 ],
  [ 11, "awaiting_refund",   54,  47_900, 1 ],
  [ 7,  "delivered",         61, 184_500, 4 ],
  [ 3,  "cancelled",         77,  33_900, 1 ],
  [ 4,  "delivered",         89,  78_600, 2 ],
  [ 5,  "delivered",        112,  51_900, 1 ],
  [ 9,  "delivered",        146, 143_200, 3 ],
  [ 10, "awaiting_payment",   1,  51_900, 1 ],
  [ 11, "in_production",      5,  67_400, 2 ],
  [ 13, "payment_confirmed",  3,  39_900, 1 ],
  [ 1,  "awaiting_components", 7,  88_800, 3 ],
  [ 3,  "label_issued",      11,  45_000, 1 ]
]

services = Shipping::SERVICES.keys.map(&:to_s)

orders.each_with_index do |(customer_index, status, days_ago, total_cents, quantity), index|
  order = Order.find_or_initialize_by(external_id: "demo-order-#{index + 1}")
  next unless order.new_record?

  user, city, uf = customer_records[customer_index]
  placed_at = Time.current - days_ago.days
  shipping_cents = 2990
  order.assign_attributes(
    user: user,
    number: "PG-#{placed_at.strftime('%Y%m%d')}#{format('%04d', index + 1)}",
    status: status,
    subtotal_cents: total_cents - shipping_cents,
    total_cents: total_cents,
    payment_method: status == "awaiting_payment" ? nil : %w[pix credit_card][index % 2],
    created_at: placed_at, updated_at: placed_at
  )
  order.order_items.build(
    name: "Cartucho reproduzido Prisma, pedido #{index + 1}",
    unit_price_cents: (total_cents - shipping_cents) / quantity,
    quantity: quantity
  )
  order.build_shipment(
    service: services[index % services.size],
    shipping_cents: shipping_cents,
    receiver_name: user.full_name, receiver_cpf: user.cpf,
    zip: "01310100", street: "Avenida Paulista", number: format("%03d", 100 + index),
    neighborhood: "Centro", city: city, state: uf,
    created_at: placed_at, updated_at: placed_at
  )
  order.save!
end

# A real Correios pré-postagem label (SEDEX), reused as the printable sample for
# every demo order that has reached label emission. The address shown in the UI
# comes from each order's own shipment; this is just the stand-in label PDF the
# "Imprimir etiqueta Correios" action serves. Idempotent: create-or-refresh.
sample_label = Base64.strict_encode64(File.binread(Rails.root.join("db/seeds/correios_label_sample.pdf")))
labeled_statuses = %w[label_issued shipped delivered]
demo_external_ids = (1..orders.size).map { |index| "demo-order-#{index}" }

Order.where(external_id: demo_external_ids, status: labeled_statuses).includes(:shipment).find_each do |order|
  shipment = order.shipment
  next unless shipment

  label = shipment.shipping_label || shipment.build_shipping_label
  label.update!(
    state: :ready,
    recibo_id: "demo-recibo-#{order.number}",
    filename: "etiqueta-#{order.number}.pdf",
    pdf_base64: sample_label
  )
end

# Dev-only backoffice operator so /admin is reachable locally.
# Sign in at /admin/entrar with backoffice@prismagames.dev / backoffice123.
admin = User.find_or_initialize_by(email: "backoffice@prismagames.dev")
if admin.new_record?
  admin.skip_confirmation_notification!
  admin.assign_attributes(
    full_name: "Vinícius Nunes", cpf: valid_cpf("123456780"), phone: "11990001122",
    admin: true, confirmed_at: Time.current,
    password: "backoffice123", password_confirmation: "backoffice123"
  )
  admin.save!
end

puts "Backoffice demo: #{customer_records.size} customers, #{orders.size} orders, 1 dev admin (backoffice@prismagames.dev / backoffice123)."
