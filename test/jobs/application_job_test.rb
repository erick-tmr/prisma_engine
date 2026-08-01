require "test_helper"

class ApplicationJobTest < ActiveJob::TestCase
  test "a job enqueued inside a transaction is held back until the commit" do
    assert_enqueued_with(job: SyncGameOfTheMonthCatalogJob) do
      ActiveRecord::Base.transaction do
        SyncGameOfTheMonthCatalogJob.perform_later([])
        assert_no_enqueued_jobs only: SyncGameOfTheMonthCatalogJob
      end
    end
  end

  test "a job enqueued inside a transaction never reaches the queue when it rolls back" do
    assert_no_enqueued_jobs only: SyncGameOfTheMonthCatalogJob do
      ActiveRecord::Base.transaction do
        SyncGameOfTheMonthCatalogJob.perform_later([])
        raise ActiveRecord::Rollback
      end
    end
  end
end
