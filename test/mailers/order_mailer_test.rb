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
  end

  test "delivery_issue explains the problem and shows the tracking code" do
    order = orders(:delivered)
    email = OrderMailer.delivery_issue(order)

    assert_equal "Problema na entrega do pedido #{order.number}", email.subject
    body = email.html_part.body.to_s
    assert_includes body, "problema na entrega"
    assert_includes body, order.shipment.tracking_code
    assert_includes body, "Falar com o suporte"
    assert_includes body, "dragon-letter-full.png"
  end
end
