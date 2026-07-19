module Orders
  class MergedObservation
    def self.call(master:, folded:)
      new(master: master, folded: folded).call
    end

    def initialize(master:, folded:)
      @master = master
      @folded = folded
    end

    def call
      return master.observation if extras.empty?

      lines = [ master.observation.presence, *extras ].compact
      lines.delete_at(drop_offset) while lines.length > 1 && too_long?(lines)
      lines.join("\n")
    end

    private

    attr_reader :master, :folded

    def extras
      @extras ||= folded
                  .select { |order| order.observation.present? }
                  .sort_by(&:created_at)
                  .map { |order| "[#{order.number}] #{order.observation}" }
    end

    def drop_offset
      master.observation.present? ? 1 : 0
    end

    def too_long?(lines)
      lines.join("\n").length > Order::OBSERVATION_STORAGE_LIMIT
    end
  end
end
