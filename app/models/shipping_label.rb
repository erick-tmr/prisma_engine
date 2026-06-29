class ShippingLabel < ApplicationRecord
  belongs_to :shipment

  enum :state, { pending: 0, prepost_created: 1, requested: 2, ready: 3, prepost_confirmed: 4, requesting: 5 }

  def mark_prepost_created!
    update!(state: :prepost_created, error: nil, errored_at: nil)
  end

  def mark_prepost_confirmed!
    update!(state: :prepost_confirmed, error: nil, errored_at: nil)
  end

  def claim_requesting!
    claimed = self.class.where(id: id, state: :prepost_confirmed).update_all(state: :requesting)
    reload
    claimed == 1
  end

  def unclaim_requesting!
    self.class.where(id: id, state: :requesting).update_all(state: :prepost_confirmed)
    reload
  end

  def mark_requested!(recibo_id)
    update!(state: :requested, recibo_id: recibo_id, error: nil, errored_at: nil)
  end

  def mark_ready!(filename:, pdf:)
    update!(state: :ready, filename: filename, pdf_base64: pdf, error: nil, errored_at: nil)
  end

  def reset_for_relabel!
    update!(
      state: :prepost_confirmed, recibo_id: nil, error: nil, errored_at: nil,
      relabel_attempts: relabel_attempts + 1
    )
  end

  def record_error!(message)
    update!(error: message, errored_at: Time.current)
  end

  def pdf_bytes
    Base64.decode64(pdf_base64) if pdf_base64
  end
end
