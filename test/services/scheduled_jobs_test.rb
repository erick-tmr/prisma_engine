require "test_helper"

class ScheduledJobsTest < ActiveSupport::TestCase
  test "does nothing without a booking id" do
    assert_nil ScheduledJobs.cancel(nil)
    assert_nil ScheduledJobs.cancel("")
  end

  test "does nothing when solid_queue is not the adapter" do
    assert_nil ScheduledJobs.cancel("d1e2f3")
  end

  test "discards the booking that solid_queue is holding" do
    discarded = false
    booking = Object.new
    booking.define_singleton_method(:discard) { discarded = true }

    ActiveJob::Base.stub(:queue_adapter_name, "solid_queue") do
      SolidQueue::Job.stub(:find_by, booking) { ScheduledJobs.cancel("d1e2f3") }
    end

    assert discarded
  end

  test "tolerates a booking that solid_queue has already dropped" do
    ActiveJob::Base.stub(:queue_adapter_name, "solid_queue") do
      SolidQueue::Job.stub(:find_by, nil) { assert_nil ScheduledJobs.cancel("d1e2f3") }
    end
  end
end
