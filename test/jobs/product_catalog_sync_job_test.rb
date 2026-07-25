require "test_helper"

class ProductCatalogSyncJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "returns without touching the domain when the product is gone" do
    assert_nothing_raised { ProductCatalogSyncJob.perform_now(-1) }
  end

  test "delegates to ProductSync for an existing product" do
    product = products(:yellow)
    seen = nil

    Catalog::ProductSync.stub(:call, ->(arg) { seen = arg }) do
      ProductCatalogSyncJob.perform_now(product.id)
    end

    assert_equal product, seen
  end

  test "retries on a transient Meta error" do
    product = products(:yellow)

    Catalog::ProductSync.stub(:call, ->(*) { raise Meta::Api::TransientError, "rate limited" }) do
      assert_enqueued_jobs 1, only: ProductCatalogSyncJob do
        ProductCatalogSyncJob.perform_now(product.id)
      end
    end
  end
end
