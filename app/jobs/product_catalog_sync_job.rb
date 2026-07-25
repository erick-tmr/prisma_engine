class ProductCatalogSyncJob < ApplicationJob
  retry_on Meta::Api::TransientError,
           ActiveRecord::Deadlocked,
           ActiveRecord::LockWaitTimeout,
           wait: :polynomially_longer, attempts: 5

  limits_concurrency to: 5, key: "meta_catalog"

  def perform(product_id)
    product = Product.find_by(id: product_id)
    return if product.nil?

    Catalog::ProductSync.call(product)
  end
end
