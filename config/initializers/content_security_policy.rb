# Be sure to restart your server when you modify this file.

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src  :self
    policy.style_src   :self, :unsafe_inline
    policy.font_src    :self
    # :blob lets the backoffice catalog editor preview a just-picked photo via a
    # local object URL before it is uploaded; stored images load from :self (Disk)
    # or the R2 public host.
    policy.img_src     :self, :data, :blob, *Array(Rails.application.config.x.r2_public_host.presence)
    policy.connect_src :self
    policy.object_src  :none
    policy.base_uri    :self
  end

  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
