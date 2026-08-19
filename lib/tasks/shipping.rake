namespace :shipping do
  desc "List Correios tracking event codes we have seen but do not catalogue in TrackingUpdate::EVENT_SIGNALS"
  task uncatalogued: :environment do
    pattern = ENV["LOGS"]
    findings = pattern ? Shipping::UncataloguedEvents.from_paths(pattern) : Shipping::UncataloguedEvents.from_database
    source = pattern || "database"

    if findings.empty?
      puts "Every Correios event code seen in #{source} is catalogued."
      next
    end

    puts "#{findings.size} uncatalogued Correios event code(s) in #{source}:"
    puts format("  %-10s %12s %10s  %s", "CODE", "OCCURRENCES", "SHIPMENTS", "DESCRIPTION")
    findings.each do |finding|
      puts format("  %-10s %12d %10d  %s",
                  finding.signature, finding.occurrences, finding.shipments, finding.description)
    end
    abort "\nMap them in Shipping::TrackingUpdate::EVENT_SIGNALS, or they will not move an order."
  end
end
