require "test_helper"

class SyncStaleProductsJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "enqueues a sync job for each stale product" do
    Product.update_all(catalog_synced_at: 1.hour.from_now)
    stale = products(:yellow)
    stale.update_columns(catalog_synced_at: 1.day.ago)

    assert_enqueued_with(job: ProductCatalogBatchJob, args: [ [ stale.id ] ]) do
      SyncStaleProductsJob.perform_now
    end
  end

  test "skips products that are neither syncable nor previously synced" do
    Product.update_all(catalog_synced_at: 1.hour.from_now)
    Product.create!(
      name: "Rascunho", category: categories(:gb_color), weight_grams: 60,
      price_cents: 0, published: false
    )

    assert_no_enqueued_jobs only: ProductCatalogBatchJob do
      SyncStaleProductsJob.perform_now
    end
  end

  test "schedules the collections sync after fanning out the catalog" do
    assert_enqueued_with(job: SyncMetaCollectionsJob) do
      SyncStaleProductsJob.perform_now
    end
  end
end
