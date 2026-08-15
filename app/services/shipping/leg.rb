module Shipping
  class Leg < Data.define(:emittable_statuses, :announces_label, :sender_is_store, :progress)
    Progress = Data.define(:walk, :targets, :resolutions, :issue_status, :branch_status, :notable_unmapped)

    def self.for(shipment)
      shipment.inbound? ? INBOUND : OUTBOUND
    end

    def emittable?(order)
      emittable_statuses.include?(order.status)
    end

    def announce_label(order)
      order.advance_to_label_issued!(automatic: true) if announces_label
    end

    def parties(store:, customer:)
      sender_is_store ? { sender: store, recipient: customer } : { sender: customer, recipient: store }
    end

    def observacao_for(order)
      sender_is_store ? order.number : "#{order.number} DEVOLUCAO"
    end

    OUTBOUND = new(
      emittable_statuses: Order::STATUSES - %w[cancelled],
      announces_label: true,
      sender_is_store: true,
      progress: Progress.new(
        walk: %w[label_issued shipped delivered],
        targets: {
          "in_transit"     => { advance_to: "shipped",   then_to: nil },
          "delivered"      => { advance_to: "delivered", then_to: nil },
          "returned"       => { advance_to: "shipped",   then_to: "returned" },
          "delivery_issue" => { advance_to: "shipped",   then_to: "delivery_issue" }
        },
        resolutions: { "delivered" => "delivered", "returned" => "returned" },
        issue_status: "delivery_issue",
        branch_status: "shipped",
        notable_unmapped: []
      )
    )

    INBOUND = new(
      emittable_statuses: RETURN_WALK[0..-2],
      announces_label: false,
      sender_is_store: false,
      progress: Progress.new(
        walk: RETURN_WALK,
        targets: {
          "in_transit" => { advance_to: "returning", then_to: nil },
          "delivered"  => { advance_to: "returned",  then_to: nil }
        },
        resolutions: {},
        issue_status: nil,
        branch_status: nil,
        notable_unmapped: %w[delivery_issue returned]
      )
    )
  end
end
