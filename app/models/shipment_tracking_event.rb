class ShipmentTrackingEvent < ApplicationRecord
  belongs_to :shipment

  POSTED = %w[PO 01].freeze

  def summary
    description.presence || "#{event_code}/#{event_type}"
  end

  def detail
    payload["detalhe"].presence
  end

  def destination
    unit_location(payload["unidadeDestino"])
  end

  def posting_unit
    return unless [ event_code, event_type ] == POSTED

    unit_location(payload["unidade"])
  end

  private

  def unit_location(unit)
    unit = unit.to_h
    return if unit.blank?

    address = unit["endereco"].to_h
    [ unit["tipo"], address["cidade"], address["uf"] ].compact_blank.join(" - ").presence
  end
end
