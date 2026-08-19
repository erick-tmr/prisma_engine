require "test_helper"

module Admin
  class OrderSearchTest < ActiveSupport::TestCase
    def numbers(params)
      OrderSearch.new(params).relation.map(&:number)
    end

    def merged_order
      order = orders(:awaiting).user.orders.create!(subtotal_cents: 100, total_cents: 100)
      order.update_column(:status, "merged")
      order
    end

    test "with no params it lists every order but the consolidated ones, newest first" do
      merged = merged_order

      result = numbers({})
      assert_not_includes result, merged.number
      assert_equal Order.where.not(status: "merged").order(created_at: :desc).pluck(:number), result
    end

    test "ticking merged is the only way to surface a consolidated order" do
      merged = merged_order

      assert_includes numbers({ status: [ "merged" ] }), merged.number
      assert_not_includes numbers({ status: [ "shipped" ] }), merged.number
    end

    test "label_expired filters to orders whose pré-postagem expired, not every label_issued one" do
      expired = orders(:labeled)
      expired.shipment.expire_prepost(label: "Etiqueta expirada", at: 1.day.ago)
      expired.shipment.save!
      healthy = orders(:shipped_order)
      healthy.update_column(:status, "label_issued")

      result = numbers({ status: [ "label_expired" ] })

      assert_includes result, expired.number
      assert_not_includes result, healthy.number
    end

    test "label_expired combines with a real status instead of replacing it" do
      expired = orders(:labeled)
      expired.shipment.expire_prepost(label: "Etiqueta expirada", at: 1.day.ago)
      expired.shipment.save!
      producing = orders(:producing)

      result = numbers({ status: [ "label_expired", "in_production" ] })

      assert_includes result, expired.number
      assert_includes result, producing.number
    end

    test "label_expired is accepted as a filter even though it is not an Order status" do
      assert_not_includes Order::STATUSES, "label_expired"
      assert_equal [ "label_expired" ], OrderSearch.new({ status: [ "label_expired" ] }).statuses
    end

    test "an unknown status is discarded rather than filtering everything away" do
      search = OrderSearch.new({ status: [ "not_a_status", "shipped" ] })
      assert_equal [ "shipped" ], search.statuses
    end

    test "the query matches a client name or an order number, case-insensitively" do
      order = orders(:confirmed_paid)

      assert_includes numbers({ q: order.number.downcase }), order.number
      assert_includes numbers({ q: order.user.full_name.upcase }), order.number
      assert_empty numbers({ q: "zzzz-no-such-thing" })
    end

    test "a percent sign in the query is matched literally, not as a wildcard" do
      assert_empty numbers({ q: "%" })
    end

    test "the period covers whole days at both ends" do
      order = orders(:confirmed_paid)
      day = order.created_at.to_date.iso8601

      assert_includes numbers({ de: day, ate: day }), order.number,
                      "an order created mid-day must fall inside a single-day range"
    end

    test "an open-ended or unparseable period is tolerated" do
      assert_nil OrderSearch.new({ de: "not-a-date" }).from
      assert_nil OrderSearch.new({}).to
      assert_equal Date.new(2026, 6, 1), OrderSearch.new({ de: "2026-06-01" }).from
      assert_not_empty numbers({ de: "2000-01-01" })
      assert_not_empty numbers({ ate: "2100-01-01" })
      assert_empty numbers({ ate: "2000-01-01" })
    end

    test "status sorts by workflow position, not alphabetically" do
      result = OrderSearch.new({ sort: "status", dir: "asc" }).relation.map(&:status).uniq
      assert_equal result.sort_by { |s| Order::STATUSES.index(s) }, result
    end

    test "client sorts by name and total sorts numerically" do
      by_name = OrderSearch.new({ sort: "client", dir: "asc" }).relation.map { |o| o.user.full_name }
      assert_equal by_name.sort_by(&:downcase), by_name

      totals = OrderSearch.new({ sort: "total", dir: "desc" }).relation.map(&:total_cents)
      assert_equal totals.sort.reverse, totals
    end

    test "sort defaults to newest first and each key carries its own default direction" do
      assert_equal "date", OrderSearch.new({}).sort
      assert_equal "desc", OrderSearch.new({}).direction
      assert_equal "asc", OrderSearch.new({ sort: "client" }).direction
      assert_equal "desc", OrderSearch.new({ sort: "total" }).direction
      assert_equal "desc", OrderSearch.new({ sort: "client", dir: "desc" }).direction
    end

    test "an unknown sort key or direction falls back to the default" do
      search = OrderSearch.new({ sort: "total; DROP TABLE orders", dir: "sideways" })
      assert_equal "date", search.sort
      assert_equal "desc", search.direction
      assert_nothing_raised { search.relation.load }
    end

    test "total_cents sums the filtered set, not the page" do
      search = OrderSearch.new({ status: [ "delivered" ] })
      assert_equal Order.where(status: "delivered").sum(:total_cents), search.total_cents
    end

    test "to_params keeps only what differs from the defaults" do
      assert_empty OrderSearch.new({}).to_params
      assert_empty OrderSearch.new({ sort: "date", dir: "desc" }).to_params

      params = OrderSearch.new({ q: " ana ", status: [ "shipped" ], de: "2026-06-01", sort: "total", dir: "asc" }).to_params
      assert_equal({ q: "ana", status: [ "shipped" ], de: "2026-06-01", sort: "total", dir: "asc" }, params)
    end

    test "period_params exposes just the range, for the production report link" do
      assert_empty OrderSearch.new({}).period_params
      assert_equal({ de: "2026-06-01", ate: "2026-06-30" },
                   OrderSearch.new({ de: "2026-06-01", ate: "2026-06-30" }).period_params)
    end

    test "filtered? reports whether the operator narrowed anything" do
      assert_not OrderSearch.new({}).filtered?
      assert_not OrderSearch.new({ sort: "total" }).filtered?
      assert OrderSearch.new({ q: "ana" }).filtered?
      assert OrderSearch.new({ status: [ "shipped" ] }).filtered?
      assert OrderSearch.new({ ate: "2026-06-30" }).filtered?
    end
  end
end
