module Admin
  class ReturnsController < BaseController
    def create
      order = find_order
      result = Shipping::StartReturn.call(order: order, actor: current_user, service: params[:service],
                                          reason: params[:reason], payer: params[:payer])
      respond_with(order, result, "started")
    end

    def quote
      shipment = find_order.shipment
      return head(:not_found) unless shipment

      render json: Shipping::ReturnQuote.call(shipment).transform_values { |cents| priced(cents) }
    rescue Correios::Api::Error
      head :bad_gateway
    end

    def destroy
      order = find_order
      result = Shipping::CancelReturn.call(order: order, actor: current_user)
      respond_with(order, result, "cancelled")
    end

    private

    def find_order
      Order.find_by!(number: params[:number])
    end

    def priced(cents)
      cents && { price_cents: cents, price_formatted: HasMoney.format(cents) }
    end

    def respond_with(order, result, notice_key)
      flash_for(result, notice_key)
      # nosemgrep: ruby.rails.security.audit.xss.avoid-redirect.avoid-redirect -- internal path helper from a DB record, not a user-supplied URL
      redirect_to admin_order_path(order)
    end

    def flash_for(result, notice_key)
      if result.success?
        flash[:notice] = t("admin.orders.returns.#{notice_key}")
      else
        flash[:alert] = t("admin.orders.returns.errors.#{result.error}")
      end
    end
  end
end
