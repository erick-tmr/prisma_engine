module Catalog
  class ProductBatchSync
    def self.call(products)
      new(products).call
    end

    def initialize(products)
      @products = products.to_a
    end

    def call
      return unless Meta::Api.configured?
      return if pairs.empty?

      apply(Meta::Api::Catalog.batch(pairs.map(&:last)))
    rescue Meta::Api::PermanentError => error
      record_failure(error)
    end

    private

    attr_reader :products

    def pairs
      @pairs ||= products.filter_map do |product|
        request = request_for(product)
        [ product, request ] if request
      end
    end

    def request_for(product)
      if product.syncable_to_meta?
        { method: "UPDATE", data: MetaProductPayload.call(product).merge(id: product.id.to_s) }
      elsif product.catalog_synced_at?
        { method: "DELETE", data: { id: product.id.to_s } }
      end
    end

    def apply(response)
      errors = errors_by_retailer_id(response)
      pairs.each { |product, request| settle(product, request, errors[product.id.to_s]) }
    end

    def errors_by_retailer_id(response)
      Array(response["validation_status"]).to_h { |status| [ status["retailer_id"].to_s, message_for(status) ] }
    end

    def message_for(status)
      Array(status["errors"]).filter_map { |error| error["message"] }.join(", ").presence
    end

    def settle(product, request, error)
      if error
        product.update_columns(catalog_sync_error: error)
      elsif request[:method] == "UPDATE"
        product.update_columns(catalog_synced_at: Time.current, catalog_sync_error: nil)
      else
        product.update_columns(catalog_synced_at: nil, catalog_sync_error: nil)
      end
    end

    def record_failure(error)
      pairs.each { |product, _request| product.update_columns(catalog_sync_error: error.message) }
    end
  end
end
