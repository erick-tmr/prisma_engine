require "test_helper"

class SyncGameOfTheMonthCatalogJobTest < ActiveJob::TestCase
  test "pushes the products before rebuilding the collections that point at them" do
    steps = []
    push = ->(products) { steps << [ :items, products.map(&:id) ] }
    rebuild = -> { steps << :collections }

    Catalog::ProductBatchSync.stub(:call, push) do
      Catalog::MetaCollections.stub(:call, rebuild) do
        SyncGameOfTheMonthCatalogJob.perform_now([ products(:yellow).id ])
      end
    end

    assert_equal [ [ :items, [ products(:yellow).id ] ], :collections ], steps
  end

  test "rebuilds the collections even when no product changed hands" do
    rebuilt = false

    Catalog::ProductBatchSync.stub(:call, ->(_products) { nil }) do
      Catalog::MetaCollections.stub(:call, -> { rebuilt = true }) do
        SyncGameOfTheMonthCatalogJob.perform_now([])
      end
    end

    assert rebuilt
  end
end
