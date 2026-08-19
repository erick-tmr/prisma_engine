module Admin
  class BulkTransition
    def self.call(order_numbers:, event:, actor:)
      new(order_numbers: order_numbers, event: event, actor: actor).call
    end

    def initialize(order_numbers:, event:, actor:)
      @numbers = Array(order_numbers)
      @event = event.to_s
      @actor = actor
    end

    def call
      results = @event == "issue_label" ? issue_labels : transition_all
      summarize(results)
    end

    private

    def orders
      @orders ||= Order.where(number: @numbers)
    end

    def issue_labels
      emitting = orders.in_production.ids
      reissuing = orders.label_reissuable.ids
      Shipping::EmitLabelsJob.perform_later(emitting) if emitting.any?
      Shipping::ReissueLabelsJob.perform_later(reissuing) if reissuing.any?
      queued = (emitting + reissuing).to_set
      orders.map do |order|
        queued.include?(order.id) ? result_for(order, "queued") : result_for(order, "skipped", "not_available")
      end
    end

    def transition_all
      action = OrderActions.lookup(@event)
      return orders.map { |order| result_for(order, "skipped", "unknown_event") } if action.nil?

      orders.map { |order| transition(order, action) }
    end

    def transition(order, action)
      return result_for(order, "skipped", "not_available") unless action.available_for?(order.status)

      order.transition_to!(action.to, actor: @actor)
      result_for(order, "done")
    end

    def result_for(order, outcome, reason = nil)
      { "number" => order.number, "outcome" => outcome, "status" => order.status, "reason" => reason }
    end

    def summarize(results)
      {
        "event" => @event,
        "results" => results,
        "done" => results.count { |result| result["outcome"] == "done" },
        "queued" => results.count { |result| result["outcome"] == "queued" },
        "skipped" => results.count { |result| result["outcome"] == "skipped" }
      }
    end
  end
end
