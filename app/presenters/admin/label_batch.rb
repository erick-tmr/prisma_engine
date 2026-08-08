module Admin
  class LabelBatch
    def self.for(orders)
      new(orders.map { |order| LabelFeedback.new(order) })
    end

    def initialize(feedbacks)
      @feedbacks = feedbacks
    end

    attr_reader :feedbacks

    def empty?
      feedbacks.empty?
    end

    def total
      feedbacks.size
    end

    def settled
      feedbacks.count(&:settled?)
    end

    def failed
      feedbacks.count(&:failed?)
    end

    # A batch is the set of orders the operator just submitted, so an order with
    # no label row yet has not started rather than nothing to do: EmitLabelsJob
    # creates that row a moment after the click.
    def in_flight
      feedbacks.count { |feedback| feedback.in_flight? || feedback.state == "idle" }
    end

    def running?
      in_flight.positive?
    end

    def percent
      return 0 if empty?

      settled * 100 / total
    end

    def current_number
      feedbacks.find { |feedback| feedback.state == "running" }&.number
    end
  end
end
