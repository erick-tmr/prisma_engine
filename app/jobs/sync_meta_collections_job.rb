class SyncMetaCollectionsJob < ApplicationJob
  retry_on Meta::Api::TransientError,
           ActiveRecord::Deadlocked,
           ActiveRecord::LockWaitTimeout,
           wait: :polynomially_longer, attempts: 5

  limits_concurrency to: 1, key: "meta_collections"

  def perform
    Catalog::MetaCollections.call
  end
end
