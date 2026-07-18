module Checkout
  class MergeQuotesController < ApplicationController
    include CheckoutErrors

    before_action :authenticate_user!

    def create
      quote = MergeQuote.call(user: current_user, cart: current_cart)
      return render_error(quote.error) unless quote.eligible?

      render json: serialize(quote)
    end

    private

    def serialize(quote)
      {
        master_number:      quote.master.number,
        service:            quote.service,
        service_label:      quote.service_label,
        business_days:      quote.business_days,
        combined_cents:     quote.combined_shipping_cents,
        paid_fretes_cents:  quote.paid_fretes_cents,
        delta_cents:        quote.delta_cents,
        subtotal_cents:     quote.subtotal_cents,
        amount_cents:       quote.amount_cents,
        savings_cents:      quote.savings_cents,
        order_count:        quote.all_order_ids.length
      }
    end

    def render_error(error)
      render status: :unprocessable_entity, json: { error: ERROR_MESSAGES.fetch(error) }
    end
  end
end
