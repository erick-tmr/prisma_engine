require "test_helper"

class SyncShipmentJobTest < ActiveSupport::TestCase
  BASE = Correios::Api::BASE_URL

  setup do
    @prev_token = ENV["CORREIOS_API_TOKEN"]
    ENV["CORREIOS_API_TOKEN"] = "test-token"
  end

  teardown do
    ENV["CORREIOS_API_TOKEN"] = @prev_token
  end

  test "records events oldest-first and marks the shipment delivered" do
    shipment = Shipment.create!(tracking_code: "AD483393343BR", order: orders(:awaiting))
    stub_rastro(shipment.tracking_code, [ delivered, posted, label ])

    SyncShipmentJob.perform_now(shipment.id)

    shipment.reload
    assert shipment.tracking_delivered?
    assert_equal Time.utc(2026, 5, 23, 13, 58, 58), shipment.delivered_at
    assert_equal "Objeto entregue ao destinatário", shipment.last_tracking_status
    assert_equal Time.utc(2026, 5, 23, 13, 58, 58), shipment.last_tracked_at

    events = shipment.tracking_events.order(:position)
    assert_equal %w[FC PO BDE], events.map(&:event_code)
    assert_equal %w[82 01 01], events.map(&:event_type)
    assert_equal 0, events.first.position
  end

  test "advances the order through shipped to delivered when the parcel is delivered" do
    order = orders(:labeled)
    shipment = order.shipment
    shipment.update!(tracking_code: "AD483393343BR")
    stub_rastro(shipment.tracking_code, [ delivered, posted, label ])

    SyncShipmentJob.perform_now(shipment.id)

    order.reload
    assert order.delivered?
    last_two = order.status_changes.chronological.last(2)
    assert_equal %w[shipped delivered], last_two.map(&:to_status)
    assert last_two.all?(&:automatic)
  end

  test "leaves the order untouched when the object is invalid" do
    order = orders(:labeled)
    shipment = order.shipment
    shipment.update!(tracking_code: "X7")
    stub_request(:get, "#{BASE}/srorastro/v1/objetos/#{shipment.tracking_code}?resultado=T")
      .to_return(
        status: 200,
        body: { "objetos" => [ { "codObjeto" => shipment.tracking_code,
                                 "mensagem" => "SRO-019: Objeto inválido" } ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    SyncShipmentJob.perform_now(shipment.id)

    assert shipment.reload.tracking_unavailable?
    assert order.reload.label_issued?
  end

  test "is idempotent: a re-run updates in place without duplicating rows" do
    shipment = Shipment.create!(tracking_code: "AD483393343BR", order: orders(:awaiting))
    stub_rastro(shipment.tracking_code, [ delivered, posted, label ])

    2.times { SyncShipmentJob.perform_now(shipment.id) }

    assert_equal 3, ShipmentTrackingEvent.where(shipment: shipment).count
  end

  test "marks in_transit when posted but not yet delivered" do
    shipment = Shipment.create!(tracking_code: "X1", order: orders(:awaiting))
    stub_rastro(shipment.tracking_code, [ posted, label ])

    SyncShipmentJob.perform_now(shipment.id)

    shipment.reload
    assert shipment.tracking_in_transit?
    assert_nil shipment.delivered_at
  end

  test "stays pending when only the label was issued" do
    shipment = Shipment.create!(tracking_code: "X2", order: orders(:awaiting))
    stub_rastro(shipment.tracking_code, [ label ])

    SyncShipmentJob.perform_now(shipment.id)

    assert shipment.reload.tracking_pending?
  end

  test "logs and persists an unmapped event, treating it as in-transit" do
    shipment = Shipment.create!(tracking_code: "X4", order: orders(:awaiting))
    unknown = evento("ZZ", "99", "2026-05-24T10:00:00", "Some uncatalogued event")
    stub_rastro(shipment.tracking_code, [ unknown, posted ])

    log = capture_log { SyncShipmentJob.perform_now(shipment.id) }

    shipment.reload
    assert shipment.tracking_in_transit?
    assert_equal "ZZ", shipment.tracking_events.find_by(event_code: "ZZ")&.event_code
    assert_match(/unmapped event code=ZZ type=99/, log)
  end

  test "treats a failed delivery attempt (BDE/20) as transient in-transit, not delivered or unmapped" do
    shipment = Shipment.create!(tracking_code: "X7", order: orders(:awaiting))
    attempt = evento("BDE", "20", "2026-05-24T10:00:00", "Objeto não entregue - carteiro não atendido")
    stub_rastro(shipment.tracking_code, [ attempt, posted ])

    log = capture_log { SyncShipmentJob.perform_now(shipment.id) }

    shipment.reload
    assert shipment.tracking_in_transit?
    assert_not shipment.tracking_delivered?
    assert_no_match(/unmapped event code=BDE/, log)
  end

  test "delivered_at stays the delivery event's time even when a later event follows" do
    shipment = Shipment.create!(tracking_code: "X5", order: orders(:awaiting))
    receipt = evento("PMT", "01", "2026-05-24T08:00:00", "Comprovante de entrega disponível")
    stub_rastro(shipment.tracking_code, [ receipt, delivered, posted, label ])

    SyncShipmentJob.perform_now(shipment.id)

    shipment.reload
    assert shipment.tracking_delivered?
    assert_equal Time.utc(2026, 5, 23, 13, 58, 58), shipment.delivered_at
  end

  test "flags the shipment unavailable and records the error on an invalid object" do
    shipment = Shipment.create!(tracking_code: "X6", order: orders(:awaiting))
    stub_request(:get, "#{BASE}/srorastro/v1/objetos/#{shipment.tracking_code}?resultado=T")
      .to_return(
        status: 200,
        body: { "objetos" => [ { "codObjeto" => shipment.tracking_code,
                                 "mensagem" => "SRO-019: Objeto inválido" } ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    SyncShipmentJob.perform_now(shipment.id)

    shipment.reload
    assert shipment.tracking_unavailable?
    assert_equal "SRO-019: Objeto inválido", shipment.tracking_error
    assert_not_nil shipment.tracking_errored_at
    assert_equal 0, shipment.tracking_events.count
  end

  test "does nothing when the object has no events" do
    shipment = Shipment.create!(tracking_code: "X3", order: orders(:awaiting))
    stub_rastro(shipment.tracking_code, [])

    SyncShipmentJob.perform_now(shipment.id)

    assert_equal 0, shipment.tracking_events.count
    assert shipment.reload.tracking_pending?
    assert_nil shipment.last_tracked_at
  end

  test "is a no-op (and makes no request) when the shipment no longer exists" do
    assert_nothing_raised { SyncShipmentJob.perform_now(-1) }
  end

  private

  def stub_rastro(code, eventos)
    body = { "objetos" => [ { "codObjeto" => code, "eventos" => eventos } ] }.to_json
    stub_request(:get, "#{BASE}/srorastro/v1/objetos/#{code}?resultado=T")
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })
  end

  def delivered
    evento("BDE", "01", "2026-05-23T10:58:58", "Objeto entregue ao destinatário")
  end

  def posted
    evento("PO", "01", "2026-05-22T14:51:02", "Objeto postado")
  end

  def label
    evento("FC", "82", "2026-05-22T13:11:04", "Etiqueta emitida")
  end

  def evento(codigo, tipo, dt, descricao)
    { "codigo" => codigo, "tipo" => tipo, "dtHrCriado" => dt, "descricao" => descricao }
  end

  def capture_log
    io = StringIO.new
    previous = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = previous
  end
end
