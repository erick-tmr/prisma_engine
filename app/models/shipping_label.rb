class ShippingLabel < ApplicationRecord
  belongs_to :shipment

  enum :state, { pending: 0, prepost_created: 1, requested: 2, ready: 3, prepost_confirmed: 4,
                 requesting: 5, label_downloaded: 6 }

  def mark_prepost_created!
    update!(state: :prepost_created, error: nil, errored_at: nil)
  end

  def mark_prepost_confirmed!
    update!(state: :prepost_confirmed, error: nil, errored_at: nil)
  end

  def claim_requesting!
    claimed = self.class.where(id: id, state: :prepost_confirmed)
                  .update_all(state: :requesting, requesting_at: Time.current)
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

  def store_label!(filename:, pdf:)
    update!(state: :label_downloaded, filename: filename, pdf_base64: pdf, error: nil, errored_at: nil)
  end

  def store_dce!(filename:, pdf:)
    update!(state: :ready, dce_filename: filename, dce_base64: pdf, error: nil, errored_at: nil)
  end

  def reset_for_relabel!
    update!(
      state: :prepost_confirmed, recibo_id: nil, error: nil, errored_at: nil,
      relabel_attempts: relabel_attempts + 1
    )
  end

  def reset_for_reissue!
    update!(
      state: :pending, recibo_id: nil, filename: nil, pdf_base64: nil,
      dce_filename: nil, dce_base64: nil, error: nil, errored_at: nil,
      relabel_attempts: 0, requesting_at: nil
    )
  end

  def record_error!(message)
    update!(error: message, errored_at: Time.current)
  end

  def ready_for_retry!
    update!(error: nil, errored_at: nil, relabel_attempts: 0)
  end

  def pdf_bytes
    Base64.decode64(pdf_base64) if pdf_base64
  end

  def dce_bytes
    Base64.decode64(dce_base64) if dce_base64
  end
end
