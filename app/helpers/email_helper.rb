module EmailHelper
  def email_asset_url(filename)
    host = Rails.application.config.x.r2_public_host.to_s.chomp("/")
    "#{host}/emails/#{filename}"
  end

  def email_datetime(time)
    l(time, format: :date_at_time)
  end

  def email_date(time)
    l(time.to_date)
  end
end
