require "test_helper"

module Correios
  module Api
    class TimestampTest < ActiveSupport::TestCase
      test "parses a naive string as Brasília time" do
        # 23:59:59 -03:00 == 02:59:59 UTC the next day
        assert_equal Time.utc(2026, 6, 15, 2, 59, 59),
                     Correios::Api::Timestamp.parse("2026-06-14T23:59:59")
      end

      test "parses fractional seconds" do
        parsed = Correios::Api::Timestamp.parse("2026-05-31T22:07:02.27981743")

        assert_equal Time.utc(2026, 6, 1, 1, 7, 2), parsed.change(usec: 0)
      end

      test "honours an explicit offset" do
        # -02:00 == 01:59:59 UTC the next day
        assert_equal Time.utc(2026, 6, 15, 1, 59, 59),
                     Correios::Api::Timestamp.parse("2026-06-14T23:59:59-02:00")
      end

      test "returns nil for blank input" do
        assert_nil Correios::Api::Timestamp.parse(nil)
        assert_nil Correios::Api::Timestamp.parse("")
        assert_nil Correios::Api::Timestamp.parse("   ")
      end

      test "returns nil for an unparseable string" do
        assert_nil Correios::Api::Timestamp.parse("not a date")
        # an out-of-range date makes the zone parser raise ArgumentError
        assert_nil Correios::Api::Timestamp.parse("2026-13-99T25:61:61")
      end
    end
  end
end
