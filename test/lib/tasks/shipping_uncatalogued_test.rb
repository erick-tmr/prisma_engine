require "test_helper"
require "rake"

class ShippingUncataloguedTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("shipping:uncatalogued")
    @task = Rake::Task["shipping:uncatalogued"]
    @task.reenable
  end

  teardown { ENV.delete("LOGS") }

  test "reports nothing to do when every observed code is catalogued" do
    out, _err = capture_io { @task.invoke }

    assert_includes out, "Every Correios event code seen in database is catalogued."
  end

  test "tabulates the uncatalogued codes from the database and fails the run" do
    shipment = Shipment.create!(order: bare_order, tracking_code: "PG999000111BR")
    shipment.tracking_events.create!(position: 0, event_code: "ZZ", event_type: "99",
                                     description: "Evento misterioso")

    out, err = capture_io { assert_raises(SystemExit) { @task.invoke } }

    assert_includes out, "1 uncatalogued Correios event code(s) in database:"
    assert_match(/ZZ\/99\s+1\s+1\s+Evento misterioso/, out)
    assert_includes err, "Map them in Shipping::TrackingUpdate::EVENT_SIGNALS"
  end

  test "reads the log files named by LOGS instead of the database" do
    dir = Dir.mktmpdir
    File.write(File.join(dir, "production.log"),
               "[correios-rastro] unmapped event code=XX type=11 desc=\"Evento novo\" tracking_code=AD1BR\n")
    ENV["LOGS"] = File.join(dir, "production.log*")

    out, _err = capture_io { assert_raises(SystemExit) { @task.invoke } }

    assert_includes out, "1 uncatalogued Correios event code(s) in #{File.join(dir, 'production.log*')}:"
    assert_match(/XX\/11\s+1\s+1\s+Evento novo/, out)
  ensure
    FileUtils.remove_entry(dir)
  end
end
