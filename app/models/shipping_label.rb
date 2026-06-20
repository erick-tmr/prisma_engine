class ShippingLabel < ApplicationRecord
  belongs_to :order

  enum :state, { pending: 0, prepost_created: 1, requested: 2, ready: 3 }

  def mark_prepost_created!
    update!(state: :prepost_created, error: nil, errored_at: nil)
  end

  def mark_requested!(recibo_id)
    update!(state: :requested, recibo_id: recibo_id, error: nil, errored_at: nil)
  end

  def mark_ready!(filename:, pdf:)
    update!(state: :ready, filename: filename, pdf_base64: pdf, error: nil, errored_at: nil)
  end

  def record_error!(message)
    update!(error: message, errored_at: Time.current)
  end

  def pdf_bytes
    Base64.decode64(pdf_base64) if pdf_base64
  end
end
