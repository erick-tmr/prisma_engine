module ScheduledJobs
  module_function

  def cancel(active_job_id)
    return if active_job_id.blank?
    return unless ActiveJob::Base.queue_adapter_name == "solid_queue"

    SolidQueue::Job.find_by(active_job_id: active_job_id)&.discard
  end
end
