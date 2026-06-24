class ShipmentTrackingEvent < ApplicationRecord
  belongs_to :shipment

  # Human-readable line for the tracking timeline: the Correios descrição, falling
  # back to the raw code/type only for events that arrive without one.
  def summary
    description.presence || "#{event_code}/#{event_type}"
  end

  # Where the object is headed, for transfer events that carry a destination unit
  # ("Tipo - CIDADE - UF"), or nil. Read straight from the stored rastro payload;
  # Correios sends the city uppercase, so we surface it as-is.
  def destination
    unit = payload["unidadeDestino"].to_h
    return if unit.blank?

    address = unit["endereco"].to_h
    [ unit["tipo"], address["cidade"], address["uf"] ].compact_blank.join(" - ").presence
  end
end
