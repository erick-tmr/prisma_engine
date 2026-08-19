require "test_helper"

module Shipping
  class UncataloguedEventsTest < ActiveSupport::TestCase
    test "the database source reports every observed pair that carries no signal" do
      shipment = shipment_with(%w[ZZ 99], %w[ZZ 99], %w[PO 01])

      findings = Shipping::UncataloguedEvents.from_database
      mystery = findings.find { |finding| finding.signature == "ZZ/99" }

      assert mystery
      assert_equal 2, mystery.occurrences
      assert_equal 1, mystery.shipments
      assert_equal "Evento ZZ/99", mystery.description
      assert_not_includes findings.map(&:signature), "PO/01"
      assert_equal shipment.tracking_events.count, 3
    end

    test "the database source counts the shipments a code was seen on, not just the rows" do
      shipment_with(%w[ZZ 99])
      shipment_with(%w[ZZ 99])

      mystery = Shipping::UncataloguedEvents.from_database.find { |row| row.signature == "ZZ/99" }

      assert_equal 2, mystery.occurrences
      assert_equal 2, mystery.shipments
    end

    test "the log source tallies the warning lines the tracking sync writes" do
      findings = Shipping::UncataloguedEvents.from_logs([
        warning("ZZ", "99", "Evento misterioso", "AD741097232BR"),
        warning("ZZ", "99", "Evento misterioso", "AD741097294BR"),
        warning("XX", "11", "Evento novo", "AD741097300BR"),
        "an unrelated log line"
      ])

      assert_equal %w[ZZ/99 XX/11], findings.map(&:signature)
      assert_equal 2, findings.first.occurrences
      assert_equal 2, findings.first.shipments
      assert_equal "Evento misterioso", findings.first.description
    end

    test "the log source ignores a code that has since been catalogued" do
      findings = Shipping::UncataloguedEvents.from_logs([
        warning("BDI", "01", "Objeto entregue ao destinatário", "AD755533683BR")
      ])

      assert_empty findings
    end

    test "the log source survives a warning whose description was blank" do
      findings = Shipping::UncataloguedEvents.from_logs([
        %([correios-rastro] unmapped event code=XX type=11 desc=nil tracking_code=AD1BR)
      ])

      assert_nil findings.sole.description
      assert_equal "XX/11", findings.sole.signature
    end

    test "reading from files walks every path the pattern matches and repairs bad bytes" do
      dir = Dir.mktmpdir
      File.binwrite(File.join(dir, "production.log"),
                    %([correios-rastro] unmapped event code=XX type=11 desc="Ru\xEDdo" tracking_code=AD1BR\n).b)
      File.write(File.join(dir, "production.log.0"), warning("XX", "11", "Ruído", "AD2BR") + "\n")

      findings = Shipping::UncataloguedEvents.from_paths(File.join(dir, "production.log*"))

      assert_equal 2, findings.sole.occurrences
      assert_equal 2, findings.sole.shipments
      assert_equal "Ru\uFFFDdo", findings.sole.description
    ensure
      FileUtils.remove_entry(dir)
    end

    private

    def warning(code, type, description, tracking_code)
      "[correios-rastro] unmapped event code=#{code} type=#{type} " \
        "desc=#{description.inspect} tracking_code=#{tracking_code}"
    end

    def shipment_with(*pairs)
      shipment = Shipment.create!(order: bare_order, tracking_code: "PG#{rand(10**9)}BR")
      pairs.each_with_index do |(code, type), position|
        shipment.tracking_events.create!(position: position, event_code: code, event_type: type,
                                         description: "Evento #{code}/#{type}")
      end
      shipment
    end
  end
end
