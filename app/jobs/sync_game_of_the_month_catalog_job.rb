class SyncGameOfTheMonthCatalogJob < ApplicationJob
  retry_on Meta::Api::TransientError,
           ActiveRecord::Deadlocked,
           ActiveRecord::LockWaitTimeout,
           wait: :polynomially_longer, attempts: 5

  limits_concurrency to: 2, key: "meta_catalog"

  def perform(product_ids)
    Catalog::ProductBatchSync.call(Product.where(id: product_ids))
    Catalog::MetaCollections.call
  end
end
