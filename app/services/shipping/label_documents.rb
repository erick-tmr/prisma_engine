module Shipping
  class LabelDocuments
    def self.call(label)
      new(label).call
    end

    def initialize(label)
      @label = label
    end

    # Labels that reached ready before the DACE step existed carry only the
    # etiqueta, so the sheet is composed of whichever documents are actually
    # there rather than assuming both.
    def call
      document = CombinePDF.new
      [ label.pdf_bytes, label.dce_bytes ].compact_blank.each do |bytes|
        document << CombinePDF.parse(bytes)
      end
      document.to_pdf
    end

    private

    attr_reader :label
  end
end
