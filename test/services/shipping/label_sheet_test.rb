require "test_helper"

module Shipping
  class LabelSheetTest < ActiveSupport::TestCase
    def label_pdf(width: 200, height: 300)
      document = CombinePDF.new
      document << CombinePDF.create_page([ 0, 0, width, height ])
      Base64.strict_encode64(document.to_pdf)
    end

    def order_with_label(ready: true)
      order = Order.create!(user: users(:confirmed), subtotal_cents: 32_000, total_cents: 34_990)
      shipment = Shipment.create!(
        order: order, service: "pac", shipping_cents: 2_990,
        receiver_name: "Cliente", receiver_cpf: "52998224725", zip: "01310100",
        street: "Rua das Flores", number: "150", neighborhood: "Centro", city: "São Paulo", state: "SP"
      )
      ShippingLabel.create!(shipment: shipment, state: ready ? :ready : :pending, pdf_base64: ready ? label_pdf : nil)
      order.reload
    end

    def pages_in(pdf)
      CombinePDF.parse(pdf).pages
    end

    test "composes ready labels four to an A4 page" do
      result = LabelSheet.call(orders: Array.new(3) { order_with_label })

      assert_equal 3, result.composed
      assert_equal 0, result.skipped
      pages = pages_in(result.pdf)
      assert_equal 1, pages.count
      box = pages.first.mediabox
      assert_in_delta 595.276, box[2], 0.01
      assert_in_delta 841.89, box[3], 0.01
    end

    test "overflows onto a second A4 page beyond four labels" do
      result = LabelSheet.call(orders: Array.new(5) { order_with_label })

      assert_equal 5, result.composed
      assert_equal 2, pages_in(result.pdf).count
    end

    test "skips orders whose label is not ready and composes the rest" do
      result = LabelSheet.call(orders: [ order_with_label, order_with_label(ready: false) ])

      assert_equal 1, result.composed
      assert_equal 1, result.skipped
      assert_equal 1, pages_in(result.pdf).count
    end

    test "composes nothing when no order has a ready label" do
      result = LabelSheet.call(orders: [ order_with_label(ready: false) ])

      assert_equal 0, result.composed
      assert_equal 1, result.skipped
      assert_match(/\A%PDF/, result.pdf)
    end
  end
end
