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
      assert_includes body, "rastreamento.correios.com.br/app/index.php?objeto=PG515656028BR"
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

    html_body = email.html_part.body.to_s
    assert_includes html_body, "Ver meus pedidos"
    assert_includes html_body, "dragon-face.png"
    assert_includes html_body, "Postado"
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

    assert_includes email.html_part.body.to_s, "dragon-letter-full.png"
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
  end
end
