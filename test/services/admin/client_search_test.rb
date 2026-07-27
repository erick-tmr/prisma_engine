require "test_helper"

module Admin
  class ClientSearchTest < ActiveSupport::TestCase
    def names(params)
      ClientSearch.new(params).relation.map(&:full_name)
    end

    test "it lists customers only, never the backoffice accounts" do
      result = names({})
      assert_includes result, users(:confirmed).full_name
      assert_not_includes result, users(:admin).full_name
    end

    test "it defaults to name ascending" do
      assert_equal names({}).sort, names({})
      assert_equal "name", ClientSearch.new({}).sort
      assert_equal "asc", ClientSearch.new({}).direction
    end

    test "the query matches name, email and raw CPF digits" do
      client = users(:confirmed)

      assert_includes names({ q: client.full_name.upcase }), client.full_name
      assert_includes names({ q: client.email }), client.full_name
      assert_includes names({ q: client.cpf[0, 6] }), client.full_name
      assert_empty names({ q: "zzzz-no-such-thing" })
    end

    test "the query matches the city/UF pair the list renders" do
      address = addresses(:locked_home)

      assert_includes names({ q: "#{address.city}/#{address.state}".downcase }), address.user.full_name
      assert_includes names({ q: "/#{address.state}".downcase }), address.user.full_name
    end

    test "phone stays unsearched, matching what the list has always done" do
      client = users(:confirmed)
      skip "fixture has no phone" if client.phone.blank?

      assert_not_includes names({ q: client.phone }), client.full_name
    end

    test "each row carries its default address and order count" do
      address = addresses(:locked_home)
      row = ClientSearch.new({ q: address.user.email }).relation.first

      assert_equal address.city, row.default_city
      assert_equal address.state, row.default_state
      assert_equal address.user.orders.count, row.orders_count
    end

    test "a customer with orders but no address reports a nil city" do
      row = ClientSearch.new({ q: users(:confirmed).email }).relation.first

      assert_nil row.default_city
      assert_equal users(:confirmed).orders.count, row.orders_count
      assert_equal "active", row.situation
    end

    test "a customer with no address still returns exactly one row" do
      loner = User.create!(full_name: "Sem Endereco", email: "sem@example.com", cpf: "39053344705",
                           phone: "11988887777", password: "password123", confirmed_at: Time.current)

      rows = ClientSearch.new({ q: "sem@example.com" }).relation.to_a
      assert_equal 1, rows.size
      assert_nil rows.first.default_city
      assert_equal 0, rows.first.orders_count
      assert_equal loner.id, rows.first.id
    end

    test "situation reflects locked and unconfirmed accounts" do
      assert_equal "locked", ClientSearch.new({ q: users(:locked).email }).relation.first.situation
      assert_equal "pending", ClientSearch.new({ q: users(:unconfirmed).email }).relation.first.situation
      assert_equal "active", ClientSearch.new({ q: users(:confirmed).email }).relation.first.situation
    end

    test "it sorts by every offered key" do
      %w[name cpf city since orders status].each do |key|
        assert_nothing_raised { ClientSearch.new({ sort: key, dir: "desc" }).relation.load }
      end

      counts = ClientSearch.new({ sort: "orders", dir: "desc" }).relation.map(&:orders_count)
      assert_equal counts.sort.reverse, counts
    end

    test "an unknown sort key or direction falls back to the default" do
      search = ClientSearch.new({ sort: "cpf); DROP TABLE users --", dir: "up" })
      assert_equal "name", search.sort
      assert_equal "asc", search.direction
      assert_nothing_raised { search.relation.load }
    end

    test "to_params keeps only what differs from the defaults" do
      assert_empty ClientSearch.new({}).to_params
      assert_equal({ q: "ana", sort: "orders", dir: "desc" },
                   ClientSearch.new({ q: " ana ", sort: "orders", dir: "desc" }).to_params)
    end
  end
end
