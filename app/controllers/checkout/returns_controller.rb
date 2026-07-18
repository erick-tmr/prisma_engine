module Checkout
  class ReturnsController < ApplicationController
    include CheckoutErrors

    before_action :authenticate_user!

    layout "checkout"

    def show
      @order = current_user.orders.find_by!(number: params[:order_nsu])
      record_transaction if params[:transaction_nsu].present?
      @state = payment_state
      @order = @order.merged_into if @order.merged? && @order.merged_into
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

    def record_transaction
      @order.update!(
        external_id:    params[:transaction_nsu],
        receipt_url:    params[:receipt_url],
        payment_method: params[:capture_method]
      )
    end

    def payment_state
      return "failed" if @order.cancelled? || @order.payment_expired?

      @order.awaiting_payment? ? "pending" : "success"
    end
  end
end
