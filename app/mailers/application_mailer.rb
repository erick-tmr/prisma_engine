# :nocov:
# Rails scaffold base class — no mailers exist yet. Once a real mailer lands,
# remove the nocov markers and add tests that exercise its deliveries.
class ApplicationMailer < ActionMailer::Base
  default from: "from@example.com"
  layout "mailer"
end
# :nocov:
