module Checkout
  class ReturnsController < ApplicationController
    include CheckoutErrors

    before_action :authenticate_user!

    layout "checkout"

    def show
      @order = find_order(params[:order_nsu])
      record_transaction if params[:transaction_nsu].present?
      @state = payment_state
      @order = find_order(@order.merged_into.number) if @order.merged? && @order.merged_into
    end

    def pay
      order = current_user.orders.find_by!(number: params[:order_nsu])
      # Internal status-page path; order.number is a persisted value, not user input.
      # nosemgrep: ruby.rails.security.audit.xss.avoid-redirect.avoid-redirect
      return redirect_to checkout_return_path(order_nsu: order.number) unless order.awaiting_payment?

      # Redirects to the InfinitePay hosted-checkout URL from Payments::Checkout (a trusted PSP), not user input.
      # nosemgrep: ruby.rails.security.audit.xss.avoid-redirect.avoid-redirect
      redirect_to Payments::Checkout.start(order, redirect_url: checkout_return_url, webhook_url: payments_webhook_url(order.webhook_token)),
                  allow_other_host: true
    rescue InfinitePay::Api::Error
      flash[:alert] = ERROR_MESSAGES[:payment_error]
      redirect_to checkout_return_path(order_nsu: params[:order_nsu])
    end

    private

    def find_order(number)
      current_user.orders.includes(order_items: OrderItem::PHOTO_INCLUDES).find_by!(number:)
    end

    def record_transaction
      verified = Payments::Verification.call(order: @order, payload: return_payload)
      return unless verified.verified?

      @order.update!(
        external_id:    verified.payload["transaction_nsu"],
        receipt_url:    verified.payload["receipt_url"],
        payment_method: verified.payload["capture_method"],
        invoice_slug:   verified.payload["invoice_slug"]
      )
    rescue InfinitePay::Api::Error
      Rails.logger.warn("[Checkout::ReturnsController] order=#{@order.number} could not reach infinitepay to verify the transaction")
    end

    def return_payload
      {
        "order_nsu"       => @order.number,
        "transaction_nsu" => params[:transaction_nsu],
        "invoice_slug"    => params[:slug],
        "receipt_url"     => params[:receipt_url]
      }
    end

    def payment_state
      return "failed" if @order.cancelled? || @order.payment_expired?

      @order.awaiting_payment? ? "pending" : "success"
    end
  end
end
