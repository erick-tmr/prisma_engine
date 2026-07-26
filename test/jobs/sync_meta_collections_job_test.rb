require "test_helper"

class SyncMetaCollectionsJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "delegates to MetaCollections" do
    called = false

    Catalog::MetaCollections.stub(:call, -> { called = true }) do
      SyncMetaCollectionsJob.perform_now
    end

    assert called
  end

  test "retries on a transient Meta error" do
    Catalog::MetaCollections.stub(:call, -> { raise Meta::Api::TransientError, "rate limited" }) do
      assert_enqueued_jobs 1, only: SyncMetaCollectionsJob do
        SyncMetaCollectionsJob.perform_now
      end
    end
  end
end
