require "test_helper"
require "rake"

class DevEmailsTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("dev:emails")
    draw_routes_before_development_is_faked
    @task = Rake::Task["dev:emails"]
    @task.reenable
    ActionMailer::Base.deliveries.clear
  end

  test "refuses to run outside development" do
    assert_raises(SystemExit) { capture_io { @task.invoke } }

    assert_empty ActionMailer::Base.deliveries
  end

  test "delivers every e-mail of every preview" do
    out, _err = run_task_with([ preview_of(%w[account_created]), preview_of(%w[account_created]) ])

    assert_equal 2, ActionMailer::Base.deliveries.size
    assert_includes out, "sent welcome/account_created"
    assert_includes out, "Inbox ready"
  end

  test "reports the previews it could not render and keeps going" do
    out, err = run_task_with([ failing_preview, preview_of(%w[account_created]) ])

    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_includes err, "failed broken/boom: RuntimeError: no record to preview"
    assert_includes out, "1 e-mail(s) failed"
  end

  private

  def draw_routes_before_development_is_faked
    Rails.application.reload_routes_unless_loaded
  end

  def run_task_with(previews)
    capture_io do
      Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) do
        ActionMailer::Preview.stub(:all, previews) { @task.invoke }
      end
    end
  end

  def preview_of(emails)
    Class.new(ActionMailer::Preview) do
      define_singleton_method(:emails) { emails }
      define_singleton_method(:preview_name) { "welcome" }
      define_singleton_method(:call) { |_email| WelcomeMailer.account_created(User.first) }
    end
  end

  def failing_preview
    Class.new(ActionMailer::Preview) do
      define_singleton_method(:emails) { %w[boom] }
      define_singleton_method(:preview_name) { "broken" }
      define_singleton_method(:call) { |_email| raise "no record to preview" }
    end
  end
end
