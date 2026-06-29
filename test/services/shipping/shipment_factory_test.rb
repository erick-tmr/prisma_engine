require "test_helper"

module Shipping
  class ShipmentFactoryTest < ActiveSupport::TestCase
    PAYLOAD = {
      "id" => "PRHelX4tO8Qsuqq0D47quwxA",
      "codigoObjeto" => "AD515656026BR",
      "codigoServico" => "03220",
      "statusAtual" => 7,
      "descStatusAtual" => "Pendente",
      "dataHoraStatusAtual" => "2026-05-31T22:07:02.27981743",
      "dataHora" => "2026-05-31T22:07:02",
      "prazoPostagem" => "2026-06-14T23:59:59"
    }.freeze

    setup { @shipment = shipments(:awaiting) }

    test "updates the planned shipment with the Correios response, leaving our snapshot intact" do
      Shipping::ShipmentFactory.update_from_pre_postagem(@shipment, PAYLOAD)

      @shipment.reload
      assert_equal "PRHelX4tO8Qsuqq0D47quwxA", @shipment.pre_post_id
      assert_equal "AD515656026BR", @shipment.tracking_code
      assert_equal "03220", @shipment.service_code
      assert_equal 7, @shipment.correios_status
      assert_equal :pendente, @shipment.correios_status_name
      assert_equal "Pendente", @shipment.correios_status_label
      # 23:59:59 Brasília (-03:00) == 02:59:59 UTC the next day
      assert_equal Time.utc(2026, 6, 15, 2, 59, 59), @shipment.posting_deadline
      assert_equal PAYLOAD, @shipment.pre_post_payload

      assert_equal "pac", @shipment.service
      assert_equal 120, @shipment.weight_grams
    end

    test "first-writer-wins: a duplicate pré-postagem is discarded, keeping the first pinned" do
      Shipping::ShipmentFactory.update_from_pre_postagem(@shipment, PAYLOAD)

      log = capture_log do
        Shipping::ShipmentFactory.update_from_pre_postagem(
          @shipment,
          PAYLOAD.merge(
            "id" => "OTHER-PREPOST", "codigoObjeto" => "ZZ999999999BR",
            "statusAtual" => 3, "descStatusAtual" => "Postado"
          )
        )
      end

      @shipment.reload
      assert_equal "PRHelX4tO8Qsuqq0D47quwxA", @shipment.pre_post_id
      assert_equal "AD515656026BR", @shipment.tracking_code
      assert_equal 7, @shipment.correios_status
      assert_match(/discarded duplicate/, log)
    end

    test "accepts a JSON string payload" do
      Shipping::ShipmentFactory.update_from_pre_postagem(@shipment, PAYLOAD.to_json)

      assert_equal "AD515656026BR", @shipment.reload.tracking_code
    end

    test "logs an error for an unmapped status but still persists it" do
      log = capture_log do
        Shipping::ShipmentFactory.update_from_pre_postagem(
          @shipment, PAYLOAD.merge("statusAtual" => 8, "descStatusAtual" => "Novo status")
        )
      end

      @shipment.reload
      assert_equal 8, @shipment.correios_status
      assert_equal "Novo status", @shipment.correios_status_label
      assert_nil @shipment.correios_status_name
      assert_match(/unknown status=8/, log)
    end

    test "persists a payload without a status without logging an error" do
      log = capture_log do
        Shipping::ShipmentFactory.update_from_pre_postagem(
          @shipment, PAYLOAD.except("statusAtual", "descStatusAtual")
        )
      end

      assert_nil @shipment.reload.correios_status
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
