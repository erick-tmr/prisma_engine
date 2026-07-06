module EmailResendCooldown
  extend ActiveSupport::Concern

  COOLDOWN = 60.seconds
  IP_CAP = 10
  IP_WINDOW = 1.hour

  class_methods do
    def enforce_resend_cooldown(flow:, redirect_to:)
      before_action(only: :create) { guard_resend_cooldown(flow, redirect_to) }
    end
  end

  private

  def guard_resend_cooldown(flow, path_helper)
    email = normalized_resend_email
    return if email.blank?

    deadline = Rails.cache.read(resend_cooldown_key(flow, email))
    return deny_resend(path_helper, email, cooldown_alert(deadline)) if deadline
    return deny_resend(path_helper, email, t("auth.resend.ip_limit")) if resend_ip_exceeded?

    record_resend_cooldown(flow, email)
    bump_resend_ip_counter
  end

  def normalized_resend_email
    params.dig(resource_name, :email).to_s.strip.downcase
  end

  def resend_cooldown_key(flow, email)
    "resend:#{flow}:#{email.to_s.strip.downcase}"
  end

  def record_resend_cooldown(flow, email)
    Rails.cache.write(resend_cooldown_key(flow, email), COOLDOWN.from_now, expires_in: COOLDOWN)
  end

  def resend_deadline(flow, email)
    Rails.cache.read(resend_cooldown_key(flow, email))
  end

  def cooldown_alert(deadline)
    t("auth.resend.cooldown", seconds: [ (deadline - Time.current).ceil, 0 ].max)
  end

  def deny_resend(path_helper, email, alert)
    flash[:alert] = alert
    redirect_to send(path_helper, email: email)
  end

  def resend_ip_exceeded?
    resend_ip_count >= IP_CAP
  end

  def resend_ip_count
    Rails.cache.read(resend_ip_key).to_i
  end

  def bump_resend_ip_counter
    Rails.cache.write(resend_ip_key, resend_ip_count + 1, expires_in: IP_WINDOW)
  end

  def resend_ip_key
    "resend:ip:#{request.remote_ip}"
  end
end
