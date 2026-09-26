module Admin
  class MergePanel
    SCOPE = "admin.orders.merge".freeze

    Row = Data.define(:order, :reason, :merged_here) do
      def eligible?
        reason.nil? && !merged_here
      end

      def item_count
        order.order_items.sum(&:quantity)
      end

      def custom_order?
        order.order_items.any?(&:custom_order?)
      end
    end

    def initialize(master)
      @master = master
    end

    attr_reader :master

    def master_reason
      @master_reason ||= Orders::MergeEligibility.for(master, origin: :backoffice).reason
    end

    def master_eligible?
      master_reason.nil?
    end

    def lock_reason
      I18n.t(reason_key("master_reasons", master_reason, master))
    end

    def rows
      @rows ||= master.user.orders.where.not(id: master.id)
                      .includes(:order_items, shipment: :shipping_label)
                      .recent_first
                      .map { |order| row_for(order) }
    end

    def eligible_rows
      master_eligible? ? rows.select(&:eligible?) : []
    end

    def blocked_rows
      rows - eligible_rows
    end

    def reason_text(row)
      return I18n.t("#{SCOPE}.merged_here") if row.merged_here
      return I18n.t("#{SCOPE}.reasons.ineligible") if row.reason.nil?

      I18n.t(reason_key("reasons", row.reason, row.order), default: I18n.t("#{SCOPE}.reasons.ineligible"))
    end

    private

    def row_for(order)
      reason = Orders::MergeEligibility.for(order, origin: :backoffice).reason
      Row.new(order: order, reason: reason, merged_here: order.merged? && order.merged_into_id == master.id)
    end

    def reason_key(group, reason, order)
      reason == :status ? "#{SCOPE}.#{group}.status.#{order.status}" : "#{SCOPE}.#{group}.#{reason}"
    end
  end
end
