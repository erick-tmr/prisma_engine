require "test_helper"

class OrderMailerTest < ActionMailer::TestCase
  test "payment_confirmed greets the customer and lists the order summary" do
    order = orders(:confirmed_paid)
    email = OrderMailer.payment_confirmed(order)

    assert_equal [ order.user.email ], email.to
    assert_equal [ "no-reply@prismagames.com.br" ], email.from
    assert_equal "Pagamento confirmado do pedido #{order.number}", email.subject

    [ email.html_part, email.text_part ].each do |part|
      body = part.body.to_s
      assert_includes body, order.user.first_name
      assert_includes body, order.number
      assert_includes body, order.order_items.first.name
      assert_includes body, "R$ 349,90"
      assert_includes body, "Seu pedido acaba de decolar!"
      assert_includes body, "Acompanhar pedido"
      assert_includes body, "Frete · #{order.shipment.service_label}"
    end

    html_body = email.html_part.body.to_s
    assert_includes html_body, "Pagamento confirmado"
    assert_includes html_body, "dragon-fly.png"
    assert_includes html_body, "Etiqueta emitida"
  end

  test "label_issued shows the tracking code that is not moving yet" do
    order = orders(:labeled)
    order.shipment.update!(tracking_code: "PG515656027BR")
    email = OrderMailer.label_issued(order)

    assert_equal "Etiqueta emitida para o pedido #{order.number}", email.subject

    [ email.html_part, email.text_part ].each do |part|
      body = part.body.to_s
      assert_includes body, order.user.first_name
      assert_includes body, "PG515656027BR"
      assert_includes body, "Ainda sem movimentação"
      assert_includes body, "Frete · PAC"
      assert_includes body, "Ver detalhes do pedido"
    end

    html_body = email.html_part.body.to_s
    assert_includes html_body, "dragon-letter-full.png"
    assert_includes html_body, "Etiqueta emitida"
    assert_not_includes html_body, "Rastrear nos Correios"
  end

  test "shipped carries the tracking link and the estimated delivery window" do
    order = orders(:shipped_order)
    order.shipment.update!(
      tracking_code: "PG515656028BR",
      delivery_business_days: 5,
      posted_at: Time.zone.parse("2026-07-22 10:00:00")
    )
    email = OrderMailer.shipped(order)

    assert_equal "Seu pedido #{order.number} foi postado nos Correios", email.subject

    [ email.html_part, email.text_part ].each do |part|
      body = part.body.to_s
      assert_includes body, "PG515656028BR"
      assert_includes body, "Entrega estimada entre"
      assert_includes body, "27 de julho"
      assert_includes body, "29 de julho"
      assert_includes body, "Rua XV de Novembro, 500 · Curitiba/PR"
      assert_includes body, "Frete · SEDEX"
      assert_includes body, "rastreamento.correios.com.br/app/index.php?objetos=PG515656028BR"
    end

    assert_includes email.text_part.body.to_s,
                    "Entrega estimada entre 27 de julho e 29 de julho, para Rua XV de Novembro, 500 · Curitiba/PR."

    html_body = email.html_part.body.to_s
    assert_includes html_body, "dragon-fly.png"
    assert_includes html_body, "Rastrear nos Correios"
  end

  test "shipped falls back to the destination alone when no delivery estimate was stored" do
    order = orders(:shipped_order)
    order.shipment.update!(tracking_code: "PG515656029BR", delivery_business_days: nil)
    email = OrderMailer.shipped(order)

    [ email.html_part, email.text_part ].each do |part|
      body = part.body.to_s
      assert_includes body, "Enviamos para"
      assert_includes body, "Rua XV de Novembro, 500 · Curitiba/PR"
      assert_not_includes body, "Entrega estimada"
    end
  end

  test "delivered carries the tracking code" do
    order = orders(:delivered)
    email = OrderMailer.delivered(order)

    assert_equal "Seu pedido #{order.number} foi entregue", email.subject
    assert_includes email.html_part.body.to_s, order.shipment.tracking_code
    assert_includes email.text_part.body.to_s, order.shipment.tracking_code
    assert_includes email.html_part.body.to_s, "Frete · #{order.shipment.service_label}"
    assert_includes email.text_part.body.to_s, "Frete · #{order.shipment.service_label}"

    html_body = email.html_part.body.to_s
    assert_includes html_body, "Ver meus pedidos"
    assert_includes html_body, "dragon-face.png"
    assert_includes html_body, "Postado"
  end

  test "returned tells the customer the package is back with us and asks how to proceed" do
    order = orders(:delivered)
    email = OrderMailer.returned(order)

    assert_equal [ order.user.email ], email.to
    assert_equal "Seu pedido #{order.number} voltou para a gente", email.subject

    [ email.html_part, email.text_part ].each do |part|
      body = part.body.to_s
      assert_includes body, order.user.first_name
      assert_includes body, "devolveram o pacote para o nosso endereço"
      assert_includes body, "Vamos analisar o motivo da devolução"
      assert_includes body, "Falar no WhatsApp"
      assert_includes body, "https://wa.me/5535920001100?text="
      assert_not_includes body, "Responda este e-mail"
      assert_not_includes body, "sem custo"
      assert_not_includes body, "por sua conta"
    end

    assert_includes email.html_part.body.to_s, "Devolvido"
    assert_includes email.html_part.body.to_s, "dragon-face.png"
  end

  test "returned opens WhatsApp with the order number already written out" do
    order = orders(:delivered)
    url = OrderMailer.returned(order).text_part.body.to_s[%r{https://wa\.me/\S+}]

    assert_includes CGI.unescape(url), "Meu pedido #{order.number} voltou pelos Correios"
  end

  test "delivery_issue falls back to the generic copy when no issue event is catalogued" do
    order = orders(:delivered)
    email = OrderMailer.delivery_issue(order)

    assert_equal "Problema na entrega do pedido #{order.number}", email.subject

    [ email.html_part, email.text_part ].each do |part|
      body = part.body.to_s
      assert_includes body, "Entre em contato com os Correios e veja como podem resolver a situação"
      assert_includes body, "conte conosco"
      assert_includes body, order.shipment.tracking_code
      assert_includes body, "Falar com os Correios"
      assert_includes body, Shipping::CORREIOS_CONTACT_URL
      assert_not_includes body, "Falar com o suporte"
      assert_not_includes body, "Nossa equipe já está cuidando disso"
    end

    assert_includes email.html_part.body.to_s, "dragon-face.png"
  end

  test "delivery_issue sends the Correios pickup copy and quotes what Correios said" do
    order = orders(:delivered)
    detalhe = "Por favor, aguarde. Será informada aqui a unidade em que o objeto ficará disponível para retirada"
    order.shipment.tracking_events.create!(
      position: 0, event_code: "BDE", event_type: "98",
      description: "Objeto não entregue - Endereço insuficiente",
      occurred_at: Time.current, payload: { "detalhe" => detalhe }
    )

    email = OrderMailer.delivery_issue(order)

    assert_equal "Os Correios não conseguiram entregar o pedido #{order.number}", email.subject

    [ email.html_part, email.text_part ].each do |part|
      body = part.body.to_s
      assert_includes body, "confirme o endereço completo"
      assert_includes body, "conte conosco"
      assert_includes body, detalhe
      assert_includes body, order.shipment.tracking_code
      assert_includes body, "Falar com os Correios"
      assert_includes body, Shipping::CORREIOS_CONTACT_URL
      assert_includes body, order.shipment.tracking_url
    end

    assert_includes email.html_part.body.to_s, "dragon-letter-full.png"
  end

  test "each delivery-issue kind gets its own hero, so the two copies do not look alike" do
    heroes = OrderMailer::ISSUE_HEROES.values

    assert_equal heroes.uniq, heroes
    assert_includes heroes, OrderMailer::DEFAULT_ISSUE_HERO
  end
  test "awaiting_return points the customer at their order page for the label" do
    order = orders(:delivered)
    Shipping::StartReturn.call(order: order)

    mail = OrderMailer.awaiting_return(order.reload)

    assert_equal [ order.user.email ], mail.to
    assert_equal I18n.t("order_mailer.awaiting_return.subject", number: order.number), mail.subject
    assert_includes mail.html_part.body.to_s, I18n.t("order_mailer.awaiting_return.page_note")
    assert_includes mail.html_part.body.to_s, order.shipment.service_label
    assert_includes mail.html_part.body.to_s, order.number
  end

  test "returning carries the return tracking code" do
    order = orders(:delivered)
    Shipping::StartReturn.call(order: order)
    order.reload.return_shipment.update!(tracking_code: "PR123456789BR")

    mail = OrderMailer.returning(order)

    assert_equal I18n.t("order_mailer.returning.subject", number: order.number), mail.subject
    assert_includes mail.html_part.body.to_s, "PR123456789BR"
  end

  test "returned blames Correios only when the package bounced back on its own" do
    bounced = OrderMailer.returned(orders(:delivered))

    assert_equal I18n.t("order_mailer.returned.bounced.subject", number: orders(:delivered).number), bounced.subject
    assert_includes bounced.html_part.body.to_s, I18n.t("order_mailer.returned.bounced.intro")
  end

  test "returned thanks the customer when they asked for the return" do
    order = orders(:delivered)
    Shipping::StartReturn.call(order: order)

    mail = OrderMailer.returned(order.reload)

    assert_equal I18n.t("order_mailer.returned.expected.subject", number: order.number), mail.subject
    assert_includes mail.html_part.body.to_s, I18n.t("order_mailer.returned.expected.intro")
  end

  test "cancelled regrets the order and invites the customer back, listing what was cancelled" do
    order = orders(:confirmed_paid)
    email = OrderMailer.cancelled(order)

    assert_equal [ order.user.email ], email.to
    assert_equal "Seu pedido #{order.number} foi cancelado", email.subject

    [ email.html_part, email.text_part ].each do |part|
      body = part.body.to_s
      assert_includes body, order.user.first_name
      assert_includes body, order.number
      assert_includes body, order.order_items.first.name
      assert_includes body, I18n.t("order_mailer.cancelled.intro")
      assert_includes body, "Ver a loja"
      assert_includes body, "Frete · #{order.shipment.service_label}"
    end

    assert_includes email.html_part.body.to_s, "Cancelado"
  end

  test "cancelled never promises a refund, because the money went back before the status moved" do
    email = OrderMailer.cancelled(orders(:confirmed_paid))

    [ email.html_part, email.text_part ].each do |part|
      assert_no_match(/reembols|devolver o valor|estorn/i, part.body.to_s)
    end
  end
end
