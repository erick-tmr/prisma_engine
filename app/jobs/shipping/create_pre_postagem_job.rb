module Shipping
  class CreatePrePostagemJob < Shipping::LabelStep
    private

    def applicable?(label)
      label.pending?
    end

    def run(order, label)
      request = Shipping::PrePostagemRequest.from_order(order)
      Shipping::CreatePrePostagem.call(request, order: order)
      label.mark_prepost_created!
    end
  end
end
