class SyncStaleProductsJob < ApplicationJob
  BATCH_SIZE = 1000

  def perform
    Product.meta_stale.in_batches(of: BATCH_SIZE) do |relation|
      ProductCatalogBatchJob.perform_later(relation.ids)
    end
    SyncMetaCollectionsJob.perform_later
  end
end
