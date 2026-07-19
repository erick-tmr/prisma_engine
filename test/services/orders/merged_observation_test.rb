require "test_helper"

module Orders
  class MergedObservationTest < ActiveSupport::TestCase
    Fake = Struct.new(:number, :observation, :created_at)

    def order(number, observation, days_old)
      Fake.new(number, observation, days_old.days.ago)
    end

    test "keeps the master note unchanged when nothing folded in carries a note" do
      master = order("PG-1", "Deixar na portaria", 5)
      folded = [ order("PG-2", nil, 4), order("PG-3", "", 3) ]

      assert_equal "Deixar na portaria", MergedObservation.call(master: master, folded: folded)
    end

    test "returns nil when no participating order has a note" do
      master = order("PG-1", nil, 5)
      folded = [ order("PG-2", nil, 4) ]

      assert_nil MergedObservation.call(master: master, folded: folded)
    end

    test "appends folded notes labelled by order, oldest to newest, after the master note" do
      master = order("PG-1", "Nota do master", 3)
      folded = [ order("PG-3", "Nota nova", 1), order("PG-2", "Nota do meio", 2) ]

      assert_equal "Nota do master\n[PG-2] Nota do meio\n[PG-3] Nota nova",
                   MergedObservation.call(master: master, folded: folded)
    end

    test "keeps only the folded notes when the master has no note" do
      master = order("PG-1", nil, 3)
      folded = [ order("PG-2", "Só esta", 1) ]

      assert_equal "[PG-2] Só esta", MergedObservation.call(master: master, folded: folded)
    end

    test "drops the oldest folded notes to fit the storage limit, keeping the most recent" do
      master = order("PG-0", "M" * 280, 10)
      folded = (1..6).map { |i| order("PG-#{i}", i.to_s * 280, 10 - i) }

      result = MergedObservation.call(master: master, folded: folded)

      assert_operator result.length, :<=, Order::OBSERVATION_STORAGE_LIMIT
      assert_includes result, "M" * 280
      assert_includes result, "[PG-6] #{'6' * 280}"
      assert_not_includes result, "[PG-1]"
    end

    test "drops the oldest folded notes to fit the limit even when the master has no note" do
      master = order("PG-0", nil, 10)
      folded = (1..6).map { |i| order("PG-#{i}", i.to_s * 280, 10 - i) }

      result = MergedObservation.call(master: master, folded: folded)

      assert_operator result.length, :<=, Order::OBSERVATION_STORAGE_LIMIT
      assert_includes result, "[PG-6] #{'6' * 280}"
      assert_not_includes result, "[PG-1]"
    end
  end
end
