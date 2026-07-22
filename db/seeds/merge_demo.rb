MARKER = "[merge-demo]".freeze
DEMO_WEIGHT = 450
DEMO_SERVICE = "pac".freeze

DEMO = [
  { status: "payment_confirmed",   age: 6.days, method: "pix",         frete: 1990 },
  { status: "awaiting_components",  age: 4.days, method: "credit_card", frete: 2490 },
  { status: "production_issue",     age: 2.days, method: "pix",         frete: 2290 }
].freeze

user = User.find_by(email: ENV["MERGE_DEMO_EMAIL"]) || User.order(:id).first
raise "No user found. Seed a user first." unless user

address = user.addresses.default_first.first || user.addresses.first
raise "Customer #{user.email} has no address. Add one first." unless address

products = Product.where(published: true).order(:id).first(3)
raise "Seed the catalog first." if products.empty?

def snapshot(address)
  {
    receiver_name: address.receiver_name, receiver_cpf: address.receiver_cpf,
    zip: address.zip, street: address.street, number: address.number,
    complement: address.complement, neighborhood: address.neighborhood,
    city: address.city, state: address.state
  }
end

orders = DEMO.each_with_index.map do |spec, index|
  product = products[index % products.size]
  order = user.orders.where(observation: MARKER, status: spec[:status]).first_or_create!(
    subtotal_cents: product.price_cents, total_cents: product.price_cents + spec[:frete],
    payment_method: spec[:method]
  )
  order.update_columns(status: spec[:status], created_at: spec[:age].ago, updated_at: spec[:age].ago)
  order.order_items.first_or_create!(
    product_id: product.id, name: product.title, unit_price_cents: product.price_cents,
    quantity: 1
  )
  attrs = { service: DEMO_SERVICE, shipping_cents: spec[:frete], weight_grams: DEMO_WEIGHT,
            height_cm: 4, width_cm: 16, length_cm: 24, **snapshot(address) }
  order.shipment ? order.shipment.update!(attrs) : order.create_shipment!(attrs)
  order
end
puts "Seeded #{orders.size} #{MARKER} orders for #{user.email}. Override target with MERGE_DEMO_EMAIL."

orders.each do |order|
  puts "  #{order.number}  #{order.status.ljust(18)} frete R$ #{'%.2f' % (order.shipment.shipping_cents / 100.0)}  #{order.shipment.weight_grams}g"
end

sample_cart = Cart::Bag.new.add(product: products.first, quantity: 1)
quote = Checkout::MergeQuote.call(user: user, cart: sample_cart)

puts "\n--- MergeQuote preview (sample cart: 1x #{products.first.title}) ---"
if quote.eligible?
  fmt = ->(cents) { "R$ #{'%.2f' % (cents / 100.0)}" }
  puts "  master (oldest):      #{quote.master.number} (frete #{fmt.call(quote.master.shipment.shipping_cents)})"
  puts "  folding in:           #{quote.absorbed_orders.map(&:number).join(', ')}"
  puts "  combined weight:      #{quote.combined_weight_grams} g"
  puts "  chosen service:       #{quote.service_label} (#{quote.service})"
  puts "  combined frete (F):   #{fmt.call(quote.combined_shipping_cents)}"
  puts "  frete delta charged:  #{fmt.call(quote.delta_cents)} (F minus the master's frete)"
  puts "  cart subtotal:        #{fmt.call(quote.subtotal_cents)}"
  puts "  amount to pay now:    #{fmt.call(quote.amount_cents)}"
  puts "  savings shown:        #{fmt.call(quote.savings_cents)}"
else
  puts "  not eligible: #{quote.error}"
end
