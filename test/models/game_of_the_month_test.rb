require "test_helper"

class GameOfTheMonthTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "requires year and month" do
    gotm = GameOfTheMonth.new
    assert_not gotm.valid?
    assert_includes gotm.errors[:year], "não pode ficar em branco"
    assert_includes gotm.errors[:month], "não pode ficar em branco"
  end

  test "rejects pre-2000 years" do
    gotm = GameOfTheMonth.new(year: 1999, month: 1)
    assert_not gotm.valid?
    assert_includes gotm.errors[:year], "deve ser maior ou igual a 2000"
  end

  test "rejects months outside 1..12" do
    [ 0, 13 ].each do |bad|
      gotm = GameOfTheMonth.new(year: 2026, month: bad)
      assert_not gotm.valid?, "expected month=#{bad} to be invalid"
    end
  end

  test "year is unique within a month" do
    GameOfTheMonth.create!(year: 2030, month: 1)
    dup = GameOfTheMonth.new(year: 2030, month: 1)
    assert_not dup.valid?
    assert_includes dup.errors[:year], "já está em uso"
  end

  test "different months in the same year are allowed" do
    GameOfTheMonth.create!(year: 2031, month: 1)
    assert GameOfTheMonth.new(year: 2031, month: 2).valid?
  end

  test "current resolves the row matching today's year/month" do
    assert_equal game_of_the_months(:current_month), GameOfTheMonth.current.first
  end

  test "for_month resolves any historical row" do
    assert_equal game_of_the_months(:past_month), GameOfTheMonth.for_month(2025, 3).first
  end

  test "current is empty when no row matches the current calendar month" do
    GameOfTheMonth.destroy_all
    assert_nil GameOfTheMonth.current.first
  end

  test "destroying a month cascades to picks and brindes" do
    gotm = game_of_the_months(:current_month)
    pick_ids   = gotm.game_of_the_month_product_ids
    brinde_ids = gotm.brinde_ids

    gotm.destroy!

    assert_empty GameOfTheMonthProduct.where(id: pick_ids)
    assert_empty Brinde.where(id: brinde_ids)
  end

  test "products are reachable through the join" do
    gotm = game_of_the_months(:current_month)
    assert_includes gotm.products, products(:yellow)
    assert_includes gotm.products, products(:placeholder)
  end

  test "current_product_ids returns the current edition's published product ids" do
    assert_equal [ products(:yellow).id, products(:placeholder).id ].sort,
                 GameOfTheMonth.current_product_ids.sort
  end

  test "current_product_ids leaves out a pick that is still a draft" do
    assert_includes game_of_the_months(:current_month).product_ids, products(:staged).id
    assert_not_includes GameOfTheMonth.current_product_ids, products(:staged).id
  end

  test "current_product_ids is empty when there is no current edition" do
    GameOfTheMonth.destroy_all
    assert_empty GameOfTheMonth.current_product_ids
  end

  test "feature_first sorts the featured ids ahead of the rest, by id within each group" do
    featured_ids = [ products(:yellow).id, products(:placeholder).id ]
    ordered = GameOfTheMonth.feature_first(Product.where(id: [
      products(:metroid).id, products(:yellow).id, products(:placeholder).id
    ]), featured_ids)

    featured = [ products(:yellow), products(:placeholder) ].sort_by(&:id)
    assert_equal featured + [ products(:metroid) ], ordered
  end

  test "feature_first leaves plain id order when no ids are featured" do
    ordered = GameOfTheMonth.feature_first(Product.where(id: [ products(:metroid).id, products(:yellow).id ]), [])

    assert_equal [ products(:yellow), products(:metroid) ].sort_by(&:id), ordered
  end

  test "publish_at defaults to midnight on the first of the edition month" do
    edition = GameOfTheMonth.create!(year: 2031, month: 8)

    assert_equal Time.zone.local(2031, 8, 1), edition.publish_at
  end

  test "an explicit publish_at survives the default" do
    chosen = Time.zone.local(2031, 8, 1, 10, 30)
    edition = GameOfTheMonth.create!(year: 2031, month: 8, publish_at: chosen)

    assert_equal chosen, edition.publish_at
  end

  test "an out of range month is rejected without deriving a publish_at" do
    edition = GameOfTheMonth.new(year: 2031, month: 13)

    assert_not edition.valid?
    assert_nil edition.publish_at
  end

  test "a missing year is rejected without deriving a publish_at" do
    edition = GameOfTheMonth.new(month: 8)

    assert_not edition.valid?
    assert_nil edition.publish_at
  end

  test "creating an edition books its publish job for the chosen time" do
    chosen = Time.zone.local(2031, 8, 1, 10, 30)

    edition = GameOfTheMonth.create!(year: 2031, month: 8, publish_at: chosen)

    assert_enqueued_with job: PublishGameOfTheMonthJob, args: [ edition.id ], at: chosen
  end

  test "moving the publish_at books a fresh job for the new time" do
    edition = GameOfTheMonth.create!(year: 2031, month: 8)
    moved = Time.zone.local(2031, 8, 1, 18, 0)

    assert_enqueued_with job: PublishGameOfTheMonthJob, args: [ edition.id ], at: moved do
      edition.update!(publish_at: moved)
    end
  end

  test "the booking id is recorded and replaced when the time moves" do
    edition = GameOfTheMonth.create!(year: 2031, month: 8)
    first = edition.reload.publish_job_id
    assert first.present?

    edition.update!(publish_at: Time.zone.local(2031, 8, 1, 18, 0))

    assert_not_equal first, edition.reload.publish_job_id
  end

  test "destroying an edition drops its booking from the queue" do
    edition = GameOfTheMonth.create!(year: 2031, month: 8)
    booked = edition.publish_job_id
    cancelled = nil

    ScheduledJobs.stub(:cancel, ->(id) { cancelled = id }) { edition.destroy! }

    assert_equal booked, cancelled
  end

  test "editing anything else does not book another job" do
    edition = GameOfTheMonth.create!(year: 2031, month: 8)

    assert_no_enqueued_jobs only: PublishGameOfTheMonthJob do
      edition.update!(note: "Especial Zelda")
    end
  end

  test "an edition that already went live is never rebooked" do
    edition = GameOfTheMonth.create!(year: 2031, month: 8)

    assert_no_enqueued_jobs only: PublishGameOfTheMonthJob do
      edition.update!(published_at: Time.current, publish_at: 1.hour.from_now)
    end
  end

  test "published_picks and published_products leave out the drafts" do
    gotm = game_of_the_months(:current_month)

    assert_equal [ products(:yellow), products(:placeholder) ].sort_by(&:id),
                 gotm.published_products.sort_by(&:id)
    assert_equal [ 0, 1 ], gotm.published_picks.map(&:position)
  end
end
