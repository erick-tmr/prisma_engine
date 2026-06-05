# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_01_005243) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "shipment_tracking_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.string "event_code"
    t.string "event_type"
    t.datetime "occurred_at"
    t.jsonb "payload", default: {}, null: false
    t.integer "position", null: false
    t.bigint "shipment_id", null: false
    t.string "tracking_code"
    t.datetime "updated_at", null: false
    t.index ["shipment_id", "position"], name: "idx_tracking_events_shipment_position", unique: true
    t.index ["shipment_id"], name: "index_shipment_tracking_events_on_shipment_id"
    t.index ["tracking_code"], name: "index_shipment_tracking_events_on_tracking_code"
  end

  create_table "shipments", force: :cascade do |t|
    t.integer "correios_status"
    t.datetime "correios_status_at"
    t.string "correios_status_label"
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.integer "height_cm"
    t.datetime "last_tracked_at"
    t.string "last_tracking_status"
    t.integer "length_cm"
    t.datetime "posted_at"
    t.datetime "posting_deadline"
    t.string "pre_post_id"
    t.jsonb "pre_post_payload", default: {}, null: false
    t.datetime "requested_at"
    t.string "service"
    t.string "service_code"
    t.string "tracking_code", null: false
    t.string "tracking_error"
    t.datetime "tracking_errored_at"
    t.integer "tracking_state", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "weight_grams"
    t.integer "width_cm"
    t.index ["pre_post_id"], name: "index_shipments_on_pre_post_id", unique: true
    t.index ["tracking_code"], name: "index_shipments_on_tracking_code", unique: true
    t.index ["tracking_state"], name: "index_shipments_on_tracking_state"
  end

  add_foreign_key "shipment_tracking_events", "shipments"
end
