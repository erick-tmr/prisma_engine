module Catalog
  class ProductSync
    def self.call(product)
      new(product).call
    end

    def initialize(product)
      @product = product
    end

    def call
      if product.syncable_to_meta?
        push
      elsif product.catalog_synced_at?
        remove
      end
    rescue Meta::Api::PermanentError => error
      product.update_columns(catalog_sync_error: error.message)
    end

    private

    attr_reader :product

    def push
      Meta::Api::Catalog.upsert(product.id.to_s, MetaProductPayload.call(product))
      product.update_columns(catalog_synced_at: Time.current, catalog_sync_error: nil)
    end

    def remove
      Meta::Api::Catalog.delete(product.id.to_s)
      product.update_columns(catalog_synced_at: nil, catalog_sync_error: nil)
    end
  end
end
