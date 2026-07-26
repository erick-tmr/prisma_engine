require "test_helper"

class ProductCatalogBatchJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "hands the loaded products to ProductBatchSync" do
    product = products(:yellow)
    seen = nil

    Catalog::ProductBatchSync.stub(:call, ->(relation) { seen = relation.to_a }) do
      ProductCatalogBatchJob.perform_now([ product.id ])
    end

    assert_equal [ product ], seen
  end

  test "retries on a transient Meta error" do
    Catalog::ProductBatchSync.stub(:call, ->(*) { raise Meta::Api::TransientError, "rate limited" }) do
      assert_enqueued_jobs 1, only: ProductCatalogBatchJob do
        ProductCatalogBatchJob.perform_now([ products(:yellow).id ])
      end
    end
  end
end
