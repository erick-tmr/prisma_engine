require "test_helper"

module Catalog
  class ProductBatchSyncTest < ActiveSupport::TestCase
    def upload
      Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/sample_product.jpg"), "image/jpeg")
    end

    def syncable_product(**attrs)
      product = Product.create!(
        { name: "Zelda", category: categories(:gb_color), weight_grams: 60, price_cents: 19_990 }.merge(attrs)
      )
      product.product_photos.create!(position: 0).image.attach(upload)
      product
    end

    def with_configured(&block)
      Meta::Api.stub(:configured?, true, &block)
    end

    test "does nothing when Meta is not configured" do
      product = syncable_product
      Catalog::ProductBatchSync.call([ product ])
      assert_nil product.reload.catalog_synced_at
    end

    test "does nothing when no product yields a request" do
      product = syncable_product(published: false)
      with_configured { Catalog::ProductBatchSync.call([ product ]) }
      assert_nil product.reload.catalog_synced_at
    end

    test "upserts syncable products and stamps them" do
      product = syncable_product
      captured = nil

      with_configured do
        Meta::Api::Catalog.stub(:batch, ->(requests) { captured = requests; { "handles" => [] } }) do
          Catalog::ProductBatchSync.call([ product ])
        end
      end

      assert_not_nil product.reload.catalog_synced_at
      assert_equal "UPDATE", captured.first[:method]
      assert_equal product.id.to_s, captured.first[:data][:id]
    end

    test "deletes previously-synced products that are no longer syncable" do
      product = syncable_product
      product.update_columns(catalog_synced_at: Time.current, published: false)
      captured = nil

      with_configured do
        Meta::Api::Catalog.stub(:batch, ->(requests) { captured = requests; {} }) do
          Catalog::ProductBatchSync.call([ product ])
        end
      end

      assert_nil product.reload.catalog_synced_at
      assert_equal "DELETE", captured.first[:method]
    end

    test "records the per-item error Meta returns and does not stamp" do
      product = syncable_product
      response = { "validation_status" => [ { "retailer_id" => product.id.to_s, "errors" => [ { "message" => "bad field" } ] } ] }

      with_configured do
        Meta::Api::Catalog.stub(:batch, ->(*) { response }) do
          Catalog::ProductBatchSync.call([ product ])
        end
      end

      assert_equal "bad field", product.reload.catalog_sync_error
      assert_nil product.catalog_synced_at
    end

    test "stamps items that come back with only a warning" do
      product = syncable_product
      response = { "validation_status" => [ { "retailer_id" => product.id.to_s, "warnings" => [ { "message" => "heads up" } ] } ] }

      with_configured do
        Meta::Api::Catalog.stub(:batch, ->(*) { response }) do
          Catalog::ProductBatchSync.call([ product ])
        end
      end

      assert_not_nil product.reload.catalog_synced_at
      assert_nil product.catalog_sync_error
    end

    test "records a batch-level permanent error on all products without raising" do
      product = syncable_product

      with_configured do
        Meta::Api::Catalog.stub(:batch, ->(*) { raise Meta::Api::PermanentError, "batch failed" }) do
          Catalog::ProductBatchSync.call([ product ])
        end
      end

      assert_equal "batch failed", product.reload.catalog_sync_error
    end

    test "lets a transient error bubble for the job to retry" do
      product = syncable_product

      assert_raises(Meta::Api::TransientError) do
        with_configured do
          Meta::Api::Catalog.stub(:batch, ->(*) { raise Meta::Api::TransientError, "rate limited" }) do
            Catalog::ProductBatchSync.call([ product ])
          end
        end
      end
    end
  end
end
