module Shipping
  class LabelSheet
    Result = Data.define(:pdf, :composed, :skipped)

    A4 = [ 0, 0, 595.276, 841.89 ].freeze
    PER_PAGE = 4
    COLS = 2
    CELL_WIDTH = 297.638
    CELL_HEIGHT = 420.945

    def self.call(orders:)
      new(orders).call
    end

    def initialize(orders)
      @orders = orders.to_a
    end

    def call
      ready = @orders.select { |order| order.shipping_label&.ready? }
      Result.new(pdf: compose(ready).to_pdf, composed: ready.size, skipped: @orders.size - ready.size)
    end

    private

    def compose(ready)
      document = CombinePDF.new
      ready.each_slice(PER_PAGE) { |slice| document << sheet_for(slice) }
      document
    end

    def sheet_for(orders)
      page = CombinePDF.create_page(A4)
      orders.each_with_index { |order, index| stamp(page, order, index) }
      page
    end

    def stamp(page, order, index)
      source = CombinePDF.parse(order.shipping_label.pdf_bytes).pages.first
      positioned = source.copy(true)
      positioned[:Contents].unshift(translation(source.mediabox, index))
      page << positioned
    end

    def translation(box, index)
      col = index % COLS
      row = index / COLS
      tx = (col * CELL_WIDTH) - box[0] + [ (CELL_WIDTH - (box[2] - box[0])) / 2, 0 ].max
      ty = A4[3] - ((row + 1) * CELL_HEIGHT) - box[1] + [ (CELL_HEIGHT - (box[3] - box[1])) / 2, 0 ].max
      { is_reference_only: true,
        referenced_object: { indirect_reference_id: 0, raw_stream_content: "1 0 0 1 #{tx} #{ty} cm" } }
    end
  end
end
