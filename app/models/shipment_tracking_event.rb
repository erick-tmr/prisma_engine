class ShipmentTrackingEvent < ApplicationRecord
  belongs_to :shipment

  # Human-readable line for the tracking timeline: the Correios descrição, falling
  # back to the raw code/type only for events that arrive without one.
  def summary
    description.presence || "#{event_code}/#{event_type}"
  end
end
