require "test_helper"

class AccountOrdersFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @shipment = shipments(:delivered)
    @shipment.tracking_events.create!(position: 1, event_code: "PO", event_type: "01",
                                      description: "Postado em São Paulo / SP", occurred_at: 16.days.ago,
                                      payload: { "unidade" => { "tipo" => "Agência dos Correios",
                                                                "endereco" => { "cidade" => "CAMBUI", "uf" => "MG" } } })
    @shipment.tracking_events.create!(position: 2, event_code: "RO", event_type: "01",
                                      description: "Objeto em trânsito, por favor aguarde", occurred_at: 13.days.ago,
                                      payload: { "unidadeDestino" => { "tipo" => "Unidade de Tratamento",
                                                                       "endereco" => { "cidade" => "SAO PAULO", "uf" => "SP" } } })
    @shipment.tracking_events.create!(position: 3, event_code: "BDE", event_type: "01",
                                      description: "Objeto entregue ao destinatário", occurred_at: 11.days.ago)
  end

  test "signed-out users hitting /minha-conta/pedidos are sent to the sign-in page" do
    get account_orders_path
    assert_redirected_to new_user_session_path
  end

  test "index lists the customer's orders newest-first" do
    sign_in users(:confirmed)
    get account_orders_path
    assert_response :success
    body = response.body
    assert_match(/PG-202606140001/, body)
    assert_match(/PG-202605270004/, body)
    assert_match(/Aguardando pagamento/, body)
    assert_match(/Entregue/, body)
    assert_operator body.index("PG-202606140001"), :<, body.index("PG-202605270004")
  end

  test "index shows the empty state for a customer with no orders" do
    sign_in users(:orderless)
    get account_orders_path
    assert_response :success
    assert_match(/Você ainda não fez nenhum pedido/, response.body)
  end

  test "index hides orders that were merged away" do
    merged = users(:confirmed).orders.create!(subtotal_cents: 100, total_cents: 100)
    merged.update_column(:status, "merged")

    sign_in users(:confirmed)
    get account_orders_path
    assert_response :success
    assert_no_match(/#{merged.number}/, response.body)
  end

  test "show on a merged order links to the order it was consolidated into" do
    master = orders(:confirmed_paid)
    merged = users(:confirmed).orders.create!(subtotal_cents: 0, total_cents: 0)
    merged.update!(merged_into: master)
    merged.update_column(:status, "merged")

    sign_in users(:confirmed)
    get account_order_path(merged)
    assert_response :success
    assert_match(/juntado ao pedido/, response.body)
    assert_select "a[href=?]", account_order_path(master)
  end

  test "show on a delivered order renders items, the tracking timeline and a paid Pix line" do
    sign_in users(:confirmed)
    get account_order_path(orders(:delivered))
    assert_response :success
    body = response.body
    assert_match(/Entregue/, body)
    assert_match(/Seu pedido foi entregue/, body)
    assert_match(/Cor da carcaça: cristal/, body)
    assert_match(/Rastreamento/, body)
    assert_match(/Código de rastreamento/, body)
    assert_match(/PG515656026BR/, body)
    assert_select "[data-tracking-copy]"
    assert_select "a[href=?][target=?]",
                  "https://rastreamento.correios.com.br/app/index.php?objetos=PG515656026BR", "_blank"
    assert_select "script[src*='order_tracking']"
    assert_match(/Objeto entregue ao destinatário/, body)
    assert_match(%r{Postado em São Paulo / SP}, body)
    assert_match(/Agência dos Correios - CAMBUI - MG/, body)
    assert_match(/Destino: Unidade de Tratamento - SAO PAULO - SP/, body)
    refute_match(%r{PO/01}, body)
    assert_match(/Pago/, body)
    assert_match(/Pix/, body)
    assert_select ".order-detail__track-item.is-current .desc", text: /entregue ao destinatário/
  end

  test "show reveals the tracking code as soon as the label is emitted, before any events" do
    shipments(:labeled).update!(tracking_code: "AD123456789BR")

    sign_in users(:buyer)
    get account_order_path(orders(:labeled))
    assert_response :success
    body = response.body
    assert_match(/Código de rastreamento/, body)
    assert_match(/AD123456789BR/, body)
    assert_select "[data-tracking-copy]"
    assert_select ".order-detail__track-item", false
  end

  test "tracking times render in Brasília time, not UTC" do
    sign_in users(:confirmed)
    @shipment.tracking_events.create!(position: 9, event_code: "OEC", event_type: "01",
                                      description: "Saiu para entrega", occurred_at: Time.utc(2026, 6, 23, 12, 42, 48))
    get account_order_path(orders(:delivered))
    assert_match(%r{23/06 09:42}, response.body)
  end

  test "show on an in-production order omits tracking and any cancel affordance" do
    sign_in users(:confirmed)
    get account_order_path(orders(:producing))
    assert_response :success
    body = response.body
    assert_match(/Em produção/, body)
    assert_no_match(/Rastreamento/, body)
    assert_no_match(/Código de rastreamento/, body)
    assert_select "[data-tracking-copy]", false
    assert_no_match(/Cancelar pedido/, body)
    assert_match(/Cartão de crédito/, body)
  end

  test "show on an awaiting-payment order renders a pending payment line and no cancel button" do
    sign_in users(:confirmed)
    get account_order_path(orders(:awaiting))
    assert_response :success
    body = response.body
    assert_no_match(/Cancelar pedido/, body)
    assert_match(/Pagamento pendente/, body)
    assert_match(/Aguardando pagamento/, body)
  end

  test "show on an unknown number is 404" do
    sign_in users(:confirmed)
    get account_order_path("PG-999999999999")
    assert_response :not_found
  end

  test "the customer-facing cancel endpoint no longer exists" do
    sign_in users(:confirmed)
    order = orders(:producing)

    post "/minha-conta/pedidos/#{order.number}/cancelar"

    assert_response :not_found
    assert order.reload.in_production?
  end

  test "every order detail page offers WhatsApp support prefilled with the order number" do
    sign_in users(:confirmed)

    [ orders(:awaiting), orders(:producing), orders(:delivered) ].each do |order|
      get account_order_path(order)
      assert_response :success
      assert_select ".order-detail__support-text",
                    text: /Precisa de ajuda sobre seu pedido\?/
      assert_select ".order-detail__support-btn[href=?][target=?][rel=?]",
                    NavHelper.whatsapp_url("Olá tenho uma dúvida com relação ao pedido número #{order.number}"),
                    "_blank", "noopener"
    end
  end

  test "a merged order still offers support even though its detail is folded away" do
    sign_in users(:confirmed)
    master = orders(:confirmed_paid)
    order = orders(:awaiting)
    order.update!(merged_into: master)
    order.transition_to!("payment_confirmed")
    order.transition_to!("merged")

    get account_order_path(order)
    assert_response :success
    assert_select ".order-detail__support-btn[href=?]",
                  NavHelper.whatsapp_url("Olá tenho uma dúvida com relação ao pedido número #{order.number}")
  end

  test "show echoes the customer's own order observation back to them" do
    sign_in users(:confirmed)
    order = orders(:producing)
    order.update!(observation: "Por favor caprichem na etiqueta JP")

    get account_order_path(order)
    assert_response :success
    assert_select ".order-detail__subcard-head", text: /Sua observação/
    assert_select ".order-detail__obs", text: "Por favor caprichem na etiqueta JP"
  end

  test "show omits the observation card when the order carries none" do
    sign_in users(:confirmed)
    get account_order_path(orders(:producing))

    assert_response :success
    assert_select ".order-detail__obs", false
  end

  test "show renders the made-to-order request the customer submitted, notes and all" do
    sign_in users(:confirmed)
    order = orders(:producing)
    order.order_items.create!(product: products(:pedido_game), name: "Pedido de jogo",
                              unit_price_cents: 19_900, quantity: 1,
                              requested_game: "Pokémon Crystal", request_notes: "Etiqueta JP se possível")

    get account_order_path(order)
    assert_response :success
    assert_select ".order-detail__pedido-head", text: /Sob encomenda/
    assert_select ".order-detail__pedido-field .v", text: "Pokémon Crystal"
    assert_select ".order-detail__pedido-field .v", text: "Etiqueta JP se possível"
  end

  test "show marks a made-to-order request with no notes as empty" do
    sign_in users(:confirmed)
    order = orders(:producing)
    order.order_items.create!(product: products(:pedido_game), name: "Pedido de jogo",
                              unit_price_cents: 19_900, quantity: 1,
                              requested_game: "Mother 3")

    get account_order_path(order)
    assert_response :success
    assert_select ".order-detail__pedido-field .v.is-empty", text: "Sem observações"
  end

  test "a customer cannot see another customer's order" do
    sign_in users(:orderless)
    get account_order_path(orders(:awaiting))
    assert_response :not_found
  end
  test "an authorized return shows the instructions and a label download" do
    order = orders(:delivered)
    sign_in order.user
    Shipping::StartReturn.call(order: order)
    ready_label!(order.reload.return_shipping_label, filename: "devolucao.pdf", pdf: Base64.strict_encode64("%PDF-1.4 devolucao"))

    get account_order_path(order)

    assert_response :success
    assert_select ".order-detail__return-btn[href=?]", return_label_account_order_path(order)
  end

  test "the return card explains the packaging limits it is asking the customer to respect" do
    order = orders(:delivered)
    sign_in order.user
    Shipping::StartReturn.call(order: order)
    ready_label!(order.reload.return_shipping_label, filename: "devolucao.pdf")

    get account_order_path(order)

    assert_response :success
    assert_select ".order-detail__return-package", text: /#{Regexp.escape(Shipping.mini_envios_weight)}/
    assert_select ".order-detail__return-package", text: /#{Regexp.escape(Shipping.mini_envios_dimensions)}/
    assert_select ".order-detail__return-package-warn"
  end

  test "a return whose label is still building says so instead of offering a download" do
    order = orders(:delivered)
    sign_in order.user
    Shipping::StartReturn.call(order: order)

    get account_order_path(order)

    assert_response :success
    assert_select ".order-detail__return-btn", false
    assert_select ".order-detail__info-body", text: /#{Regexp.escape(I18n.t("account.orders.show.return_pending"))}/
  end

  test "a posted return shows the tracking code, since the label is gone by then" do
    order = orders(:delivered)
    sign_in order.user
    Shipping::StartReturn.call(order: order)
    order.reload.return_shipment.update!(tracking_code: "PR123456789BR")
    order.transition_to!("returning", automatic: true)

    get account_order_path(order)

    assert_response :success
    assert_select ".order-detail__info-body", text: /PR123456789BR/
  end

  test "the return label downloads both documents as one PDF, and 404s for anyone else" do
    order = orders(:delivered)
    Shipping::StartReturn.call(order: order)
    ready_label!(order.reload.return_shipping_label, filename: "devolucao.pdf")

    sign_in order.user
    get return_label_account_order_path(order)
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert_equal "devolucao-#{order.number}.pdf", response.headers["Content-Disposition"][/filename="([^"]+)"/, 1]
    assert_equal 2, CombinePDF.parse(response.body).pages.size

    sign_in users(:orderless)
    get return_label_account_order_path(order)
    assert_response :not_found
  end

  test "the return label 404s while it is not ready yet" do
    order = orders(:delivered)
    sign_in order.user
    Shipping::StartReturn.call(order: order)

    get return_label_account_order_path(order)

    assert_response :not_found
  end
  test "the return label 404s for an order that has no return at all" do
    order = orders(:delivered)
    sign_in order.user

    get return_label_account_order_path(order)

    assert_response :not_found
  end
  test "the delivery and the return each get their own tracking section" do
    order = orders(:delivered)
    sign_in order.user
    Shipping::StartReturn.call(order: order)
    inbound = order.reload.return_shipment
    inbound.update!(tracking_code: "PR123456789BR")
    inbound.tracking_events.create!(position: 0, tracking_code: inbound.tracking_code, event_code: "PO",
                                    event_type: "01", description: "Objeto postado", occurred_at: 1.hour.ago)

    get account_order_path(order)

    assert_response :success
    assert_select ".order-detail__subcard-head", text: /#{I18n.t("account.orders.show.tracking")}/
    assert_select ".order-detail__subcard-head", text: /#{I18n.t("account.orders.show.return_tracking")}/
    assert_select "[data-order-tracking]", 2
    assert_select "[data-tracking-code]", text: order.shipment.tracking_code
    assert_select "[data-tracking-code]", text: "PR123456789BR"
  end

  test "an order with no return shows only the delivery tracking" do
    order = orders(:delivered)
    sign_in order.user

    get account_order_path(order)

    assert_response :success
    assert_select ".order-detail__subcard-head", text: /#{I18n.t("account.orders.show.return_tracking")}/, count: 0
  end
end
