module Shipping
  class CreatePrePostagemJob < Shipping::LabelStep
    private

    def applicable?(label)
      label.pending?
    end

    def run(shipment, label)
      request = Shipping::PrePostagemRequest.from_shipment(shipment)
      Shipping::CreatePrePostagem.call(request, shipment: shipment)
      label.mark_prepost_created!
    end
  end
end
