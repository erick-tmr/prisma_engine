module Shipping
  class LabelSheet
    Result = Data.define(:pdf, :composed, :skipped)

    A4 = [ 0, 0, 595.276, 841.89 ].freeze
    CORREIOS_LABEL_BOX = [ 9.5, 488.0, 300.0, 836.0 ].freeze
    LABEL_WIDTH = CORREIOS_LABEL_BOX[2] - CORREIOS_LABEL_BOX[0]
    LABEL_HEIGHT = CORREIOS_LABEL_BOX[3] - CORREIOS_LABEL_BOX[1]
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
      ready = @orders.select { |order| order.shipping_label&.ready? && !order.shipment.label_expired? }
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
      cropped = source.copy(true)
      cropped[:Contents].unshift(placement(index))
      page << cropped
    end

    def placement(index)
      cell_x = (index % COLS) * CELL_WIDTH
      cell_y = A4[3] - (((index / COLS) + 1) * CELL_HEIGHT)
      tx = cell_x + ((CELL_WIDTH - LABEL_WIDTH) / 2) - CORREIOS_LABEL_BOX[0]
      ty = cell_y + ((CELL_HEIGHT - LABEL_HEIGHT) / 2) - CORREIOS_LABEL_BOX[1]
      raw("#{cell_x} #{cell_y} #{CELL_WIDTH} #{CELL_HEIGHT} re W n 1 0 0 1 #{tx} #{ty} cm")
    end

    def raw(stream)
      { is_reference_only: true, referenced_object: { indirect_reference_id: 0, raw_stream_content: stream } }
    end
  end
end
