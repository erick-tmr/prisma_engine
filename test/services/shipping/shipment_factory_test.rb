require "test_helper"

module Shipping
  class ShipmentFactoryTest < ActiveSupport::TestCase
    PAYLOAD = {
      "id" => "PRHelX4tO8Qsuqq0D47quwxA",
      "codigoObjeto" => "AD515656026BR",
      "codigoServico" => "03220",
      "pesoInformado" => "120",
      "alturaInformada" => "4",
      "larguraInformada" => "16",
      "comprimentoInformado" => "24",
      "statusAtual" => 7,
      "descStatusAtual" => "Pendente",
      "dataHoraStatusAtual" => "2026-05-31T22:07:02.27981743",
      "dataHora" => "2026-05-31T22:07:02",
      "prazoPostagem" => "2026-06-14T23:59:59"
    }.freeze

    test "builds a shipment from a pré-postagem payload" do
      shipment = Shipping::ShipmentFactory.from_pre_postagem(PAYLOAD)

      assert_equal "PRHelX4tO8Qsuqq0D47quwxA", shipment.pre_post_id
      assert_equal "AD515656026BR", shipment.tracking_code
      assert_equal "03220", shipment.service_code
      assert_equal "sedex", shipment.service
      assert_equal 120, shipment.weight_grams
      assert_equal 16, shipment.width_cm
      assert_equal 4, shipment.height_cm
      assert_equal 24, shipment.length_cm
      assert_equal 7, shipment.correios_status
      assert_equal :pendente, shipment.correios_status_name
      assert_equal "Pendente", shipment.correios_status_label
      # 23:59:59 Brasília (-03:00) == 02:59:59 UTC the next day
      assert_equal Time.utc(2026, 6, 15, 2, 59, 59), shipment.posting_deadline
      assert_equal PAYLOAD, shipment.pre_post_payload
      assert shipment.persisted?
    end

    test "is idempotent on the tracking code and updates on re-run" do
      Shipping::ShipmentFactory.from_pre_postagem(PAYLOAD)

      assert_no_difference -> { Shipment.count } do
        Shipping::ShipmentFactory.from_pre_postagem(
          PAYLOAD.merge("statusAtual" => 3, "descStatusAtual" => "Postado")
        )
      end

      assert_equal 3, Shipment.sole.correios_status
    end

    test "accepts a JSON string payload" do
      shipment = Shipping::ShipmentFactory.from_pre_postagem(PAYLOAD.to_json)

      assert_equal "AD515656026BR", shipment.tracking_code
    end

    test "links the shipment to a provided order" do
      order = orders(:awaiting)
      shipment = Shipping::ShipmentFactory.from_pre_postagem(PAYLOAD, order: order)

      assert_equal order, shipment.order
    end

    test "logs an error for an unmapped status but still persists it" do
      log = capture_log do
        Shipping::ShipmentFactory.from_pre_postagem(
          PAYLOAD.merge("statusAtual" => 8, "descStatusAtual" => "Novo status")
        )
      end

      shipment = Shipment.sole
      assert_equal 8, shipment.correios_status
      assert_equal "Novo status", shipment.correios_status_label
      assert_nil shipment.correios_status_name
      assert_match(/unknown status=8/, log)
    end

    test "persists a payload without a status without logging an error" do
      log = capture_log do
        Shipping::ShipmentFactory.from_pre_postagem(PAYLOAD.except("statusAtual", "descStatusAtual"))
      end

      shipment = Shipment.sole
      assert_nil shipment.correios_status
      assert_no_match(/unknown status/, log)
    end

    private

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
end
