module Shipping
  class UncataloguedEvents
    WARNING_LINE = /
      \[correios-rastro\]\sunmapped\sevent\s
      code=(?<code>\S+)\s
      type=(?<type>\S+)\s
      desc=(?<description>.*?)\s
      tracking_code=(?<tracking_code>\S+)
    /x

    Finding = Data.define(:code, :type, :description, :occurrences, :shipments) do
      def signature
        "#{code}/#{type}"
      end
    end

    def self.from_database
      findings = Shipping::TrackingUpdate.uncatalogued_codes.map do |row|
        occurrences, shipments = counts_for(row[:code], row[:type])
        Finding.new(code: row[:code], type: row[:type], description: row[:description],
                    occurrences: occurrences, shipments: shipments)
      end
      rank(findings)
    end

    def self.from_paths(pattern)
      from_logs(lines_in(Dir[pattern].sort))
    end

    def self.lines_in(paths)
      paths.map { |path| scrubbed_lines(path) }.reduce(:+) || []
    end
    private_class_method :lines_in

    def self.scrubbed_lines(path)
      File.foreach(path, encoding: "BINARY").lazy.map { |line| line.force_encoding(Encoding::UTF_8).scrub }
    end
    private_class_method :scrubbed_lines

    def self.from_logs(lines)
      tally = Hash.new { |store, key| store[key] = { occurrences: 0, tracking_codes: Set.new, description: nil } }
      lines.each { |line| absorb(tally, line) }
      rank(tally.map { |pair, entry| finding_from(pair, entry) })
    end

    def self.absorb(tally, line)
      match = WARNING_LINE.match(line)
      return unless match
      return if Shipping::TrackingUpdate.signal_for(match[:code], match[:type])

      entry = tally[[ match[:code], match[:type] ]]
      entry[:occurrences] += 1
      entry[:tracking_codes] << match[:tracking_code]
      entry[:description] ||= describe(match[:description])
    end
    private_class_method :absorb

    def self.finding_from(pair, entry)
      Finding.new(code: pair.first, type: pair.last, description: entry[:description],
                  occurrences: entry[:occurrences], shipments: entry[:tracking_codes].size)
    end
    private_class_method :finding_from

    def self.describe(raw)
      raw == "nil" ? nil : raw.delete_prefix('"').delete_suffix('"')
    end
    private_class_method :describe

    def self.rank(findings)
      findings.sort_by { |finding| [ -finding.occurrences, finding.signature ] }
    end
    private_class_method :rank

    def self.counts_for(code, type)
      ShipmentTrackingEvent
        .where(event_code: code, event_type: type)
        .pick(Arel.sql("COUNT(*)"), Arel.sql("COUNT(DISTINCT shipment_id)"))
    end
    private_class_method :counts_for
  end
end
