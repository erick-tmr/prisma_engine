module EmailHelper
  def email_asset_url(filename)
    host = Rails.application.config.x.r2_public_host.to_s.chomp("/")
    "#{host}/emails/#{filename}"
  end
end
