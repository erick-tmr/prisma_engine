namespace :dev do
  desc "Deliver one example of every mailer e-mail to the letter_opener inbox at /cartas"
  task emails: :environment do
    abort "dev:emails only runs in development" unless Rails.env.development?

    failures = ActionMailer::Preview.all.sum do |preview|
      preview.emails.count do |email|
        preview.call(email).deliver_now
        puts "sent #{preview.preview_name}/#{email}"
        false
      rescue StandardError => error
        warn "failed #{preview.preview_name}/#{email}: #{error.class}: #{error.message}"
        true
      end
    end

    puts failures.zero? ? "Inbox ready at http://localhost:3000/cartas" : "#{failures} e-mail(s) failed, see above."
  end
end
