require "test_helper"

module Shipping
  class LabelDocumentsTest < ActiveSupport::TestCase
    setup do
      order = orders(:producing)
      @label = order.shipment.create_shipping_label!(state: :pending)
    end

    def pages_in(pdf)
      CombinePDF.parse(pdf).pages.size
    end

    test "puts the etiqueta first and the declaração second" do
      @label.store_label!(filename: "etiqueta.pdf", pdf: one_page_pdf("ETIQUETA"))
      @label.store_dce!(filename: "declaracao.pdf", pdf: one_page_pdf("DECLARACAO"))

      assert_equal 2, pages_in(Shipping::LabelDocuments.call(@label))
    end

    test "a label from before the declaração step still serves on its own" do
      @label.store_label!(filename: "etiqueta.pdf", pdf: one_page_pdf("ETIQUETA"))

      assert_equal 1, pages_in(Shipping::LabelDocuments.call(@label))
    end

    test "a label with neither document composes an empty sheet rather than raising" do
      assert_nothing_raised { Shipping::LabelDocuments.call(@label) }
    end
  end
end
