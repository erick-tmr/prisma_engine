module Admin
  class BulkTransition
    def self.call(order_numbers:, event:, actor:, service: nil)
      new(order_numbers: order_numbers, event: event, actor: actor, service: service).call
    end

    def initialize(order_numbers:, event:, actor:, service: nil)
      @numbers = Array(order_numbers)
      @event = event.to_s
      @actor = actor
      @service = service
    end

    def call
      results = case @event
      when "issue_label"      then issue_labels
      when "start_return" then start_returns
      else transition_all
      end
      summarize(results)
    end

    private

    def orders
      @orders ||= Order.where(number: @numbers)
    end

    def issue_labels
      eligible = orders.select(&:in_production?)
      Shipping::EmitLabelsJob.perform_later(eligible.map(&:id)) if eligible.any?
      orders.map { |order| order.in_production? ? result_for(order, "queued") : result_for(order, "skipped", "not_available") }
    end

    def start_returns
      orders.map do |order|
        result = Shipping::StartReturn.call(order: order, actor: @actor, service: @service)
        next result_for(order, "skipped", result.error.to_s) unless result.success?

        result_for(order.reload, "queued")
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
