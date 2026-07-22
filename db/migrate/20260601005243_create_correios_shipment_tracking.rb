class CreateCorreiosShipmentTracking < ActiveRecord::Migration[8.1]
  def change
    create_table :shipments do |t|
      t.string :tracking_code, null: false
      t.string :service
      t.string :last_tracking_status # latest rastro (tracking) event description
      t.datetime :posted_at
      t.datetime :delivered_at
      t.datetime :last_tracked_at

      # Pré-postagem fields (see Correios::PrePostagem / Shipment::CORREIOS_STATUSES)
      t.string :pre_post_id           # Correios pré-postagem id (used to call other APIs)
      t.string :service_code          # codigoServico, e.g. "03220"
      t.integer :weight_grams         # pesoInformado
      t.integer :width_cm             # larguraInformada
      t.integer :height_cm            # alturaInformada
      t.integer :length_cm            # comprimentoInformado
      t.integer :correios_status      # statusAtual
      t.string :correios_status_label # descStatusAtual
      t.datetime :correios_status_at  # dataHoraStatusAtual
      t.datetime :posting_deadline    # prazoPostagem: post by this or it's cancelled
      t.datetime :requested_at        # dataHora: pré-postagem request time
      t.jsonb :pre_post_payload, null: false, default: {} # full raw pré-postagem response
      t.integer :tracking_state, null: false, default: 0  # see Shipment#tracking_state enum
      t.string :tracking_error        # last error a rastro response returned (e.g. SRO-019)
      t.datetime :tracking_errored_at

      t.timestamps
    end
    add_index :shipments, :tracking_code, unique: true
    add_index :shipments, :pre_post_id, unique: true
    add_index :shipments, :tracking_state

    create_table :shipment_tracking_events do |t|
      t.references :shipment, null: false, foreign_key: true
      t.string :tracking_code
      t.integer :position, null: false
      t.string :event_code # rastro "codigo" (e.g. BDE)
      t.string :event_type # rastro "tipo" (e.g. 01); code+type together identify the event (BDE/01 = entregue)
      t.string :description
      t.datetime :occurred_at
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end
    add_index :shipment_tracking_events, :tracking_code
    add_index :shipment_tracking_events,
              [ :shipment_id, :position ],
              unique: true,
              name: "idx_tracking_events_shipment_position"
  end
end
