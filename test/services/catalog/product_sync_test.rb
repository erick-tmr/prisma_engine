require "test_helper"

module Catalog
  class ProductSyncTest < ActiveSupport::TestCase
    def upload
      Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/sample_product.jpg"), "image/jpeg")
    end

    def syncable_product
      product = Product.create!(
        name: "Zelda", category: categories(:gb_color), weight_grams: 60, price_cents: 19_990
      )
      product.product_photos.create!(position: 0).image.attach(upload)
      product
    end

    def with_meta_configured(&block)
      Meta::Api.stub(:configured?, true, &block)
    end

    test "pushes an upsert and stamps catalog_synced_at" do
      product = syncable_product

      with_meta_configured do
        Meta::Api::Catalog.stub(:upsert, { "handles" => [] }) do
          Catalog::ProductSync.call(product)
        end
      end

      assert_not_nil product.reload.catalog_synced_at
      assert_nil product.catalog_sync_error
    end

    test "deletes when a previously-synced product is no longer syncable" do
      product = syncable_product
      product.update_columns(catalog_synced_at: Time.current, published: false)
      removed = nil

      with_meta_configured do
        Meta::Api::Catalog.stub(:delete, ->(retailer_id) { removed = retailer_id }) do
          Catalog::ProductSync.call(product)
        end
      end

      assert_equal product.id.to_s, removed
      assert_nil product.reload.catalog_synced_at
    end

    test "does nothing when an unsyncable product was never synced" do
      product = syncable_product
      product.update_columns(published: false)

      with_meta_configured { Catalog::ProductSync.call(product) }

      assert_nil product.reload.catalog_synced_at
    end

    test "records a permanent error without raising" do
      product = syncable_product

      with_meta_configured do
        Meta::Api::Catalog.stub(:upsert, ->(*) { raise Meta::Api::PermanentError, "invalid field" }) do
          Catalog::ProductSync.call(product)
        end
      end

      assert_equal "invalid field", product.reload.catalog_sync_error
      assert_nil product.catalog_synced_at
    end

    test "lets a transient error bubble for the job to retry" do
      product = syncable_product

      assert_raises(Meta::Api::TransientError) do
        with_meta_configured do
          Meta::Api::Catalog.stub(:upsert, ->(*) { raise Meta::Api::TransientError, "rate limited" }) do
            Catalog::ProductSync.call(product)
          end
        end
      end
    end

    test "does nothing when Meta credentials are absent" do
      product = syncable_product

      Catalog::ProductSync.call(product)

      assert_nil product.reload.catalog_synced_at
    end
  end
end
