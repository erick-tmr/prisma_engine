class SyncStaleProductsJob < ApplicationJob
  def perform
    Product.meta_stale.find_each do |product|
      ProductCatalogSyncJob.perform_later(product.id)
    end
    SyncMetaCollectionsJob.perform_later
  end
end
