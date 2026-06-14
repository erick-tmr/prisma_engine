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

ActiveRecord::Schema[8.1].define(version: 2026_06_14_140000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "addresses", force: :cascade do |t|
    t.string "city", null: false
    t.string "complement"
    t.datetime "created_at", null: false
    t.boolean "default", default: false, null: false
    t.string "neighborhood", null: false
    t.string "number", null: false
    t.string "receiver_cpf", null: false
    t.string "receiver_name", null: false
    t.string "state", null: false
    t.string "street", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "zip", null: false
    t.index ["user_id", "default"], name: "index_addresses_on_user_id_and_default"
    t.index ["user_id"], name: "index_addresses_on_user_id"
  end

  create_table "brindes", force: :cascade do |t|
    t.string "caption"
    t.datetime "created_at", null: false
    t.bigint "game_of_the_month_id", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "weight_grams", default: 0, null: false
    t.index ["game_of_the_month_id"], name: "index_brindes_on_game_of_the_month_id"
  end

  create_table "categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_categories_on_slug", unique: true
  end

  create_table "friendly_id_slugs", force: :cascade do |t|
    t.datetime "created_at"
    t.string "scope"
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type"
    t.index ["sluggable_type", "sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_type_and_sluggable_id"
  end

  create_table "game_of_the_month_products", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "game_of_the_month_id", null: false
    t.integer "position", default: 0, null: false
    t.bigint "product_id", null: false
    t.datetime "updated_at", null: false
    t.index ["game_of_the_month_id", "product_id"], name: "index_gotm_products_on_month_and_product", unique: true
    t.index ["game_of_the_month_id"], name: "index_game_of_the_month_products_on_game_of_the_month_id"
    t.index ["product_id"], name: "index_game_of_the_month_products_on_product_id"
  end

  create_table "game_of_the_months", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "month", null: false
    t.text "note"
    t.datetime "updated_at", null: false
    t.integer "year", null: false
    t.index ["year", "month"], name: "index_game_of_the_months_on_year_and_month", unique: true
    t.check_constraint "month >= 1 AND month <= 12", name: "game_of_the_months_month_range"
  end

  create_table "order_items", force: :cascade do |t|
    t.jsonb "chosen_options", default: [], null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "order_id", null: false
    t.string "photo_path"
    t.bigint "product_id"
    t.integer "quantity", null: false
    t.integer "unit_price_cents", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_id"], name: "index_order_items_on_product_id"
  end

  create_table "orders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_id"
    t.string "number", null: false
    t.string "payment_method"
    t.string "receipt_url"
    t.string "ship_city", null: false
    t.string "ship_complement"
    t.string "ship_neighborhood", null: false
    t.string "ship_number", null: false
    t.string "ship_receiver_cpf", null: false
    t.string "ship_receiver_name", null: false
    t.string "ship_state", null: false
    t.string "ship_street", null: false
    t.string "ship_zip", null: false
    t.integer "shipping_cents", null: false
    t.string "shipping_service", null: false
    t.string "status", default: "awaiting_payment", null: false
    t.integer "subtotal_cents", null: false
    t.integer "total_cents", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "webhook_token"
    t.index ["external_id"], name: "index_orders_on_external_id", unique: true
    t.index ["number"], name: "index_orders_on_number", unique: true
    t.index ["user_id", "created_at"], name: "index_orders_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_orders_on_user_id"
    t.index ["webhook_token"], name: "index_orders_on_webhook_token", unique: true
  end

  create_table "payment_webhook_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "headers", default: {}, null: false
    t.bigint "order_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_payment_webhook_events_on_order_id"
  end

  create_table "product_options", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "group_name"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "price_delta_cents", default: 0, null: false
    t.bigint "product_id", null: false
    t.datetime "updated_at", null: false
    t.integer "weight_delta_grams", default: 0, null: false
    t.index ["product_id", "group_name", "name"], name: "index_product_options_uniqueness", unique: true
    t.index ["product_id"], name: "index_product_options_on_product_id"
  end

  create_table "product_photos", force: :cascade do |t|
    t.string "alt_text"
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.bigint "product_id", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_product_photos_on_product_id"
  end

  create_table "product_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.bigint "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id", "tag_id"], name: "index_product_tags_on_product_id_and_tag_id", unique: true
    t.index ["product_id"], name: "index_product_tags_on_product_id"
    t.index ["tag_id"], name: "index_product_tags_on_tag_id"
  end

  create_table "products", force: :cascade do |t|
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "BRL", null: false
    t.text "description"
    t.string "legacy_image_path"
    t.string "name", null: false
    t.integer "price_cents", default: 0, null: false
    t.boolean "published", default: true, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.integer "weight_grams", null: false
    t.index ["category_id"], name: "index_products_on_category_id"
    t.index ["published"], name: "index_products_on_published"
    t.index ["slug"], name: "index_products_on_slug", unique: true
  end

  create_table "questions", force: :cascade do |t|
    t.text "answer_body"
    t.boolean "answered", default: false, null: false
    t.datetime "answered_at"
    t.string "asker_email", null: false
    t.string "asker_name", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.boolean "published", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["product_id", "published"], name: "index_questions_on_product_id_and_published"
    t.index ["product_id"], name: "index_questions_on_product_id"
  end

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
    t.bigint "order_id"
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
    t.index ["order_id"], name: "index_shipments_on_order_id"
    t.index ["pre_post_id"], name: "index_shipments_on_pre_post_id", unique: true
    t.index ["tracking_code"], name: "index_shipments_on_tracking_code", unique: true
    t.index ["tracking_state"], name: "index_shipments_on_tracking_state"
  end

  create_table "tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_tags_on_slug", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.string "cpf", null: false
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.string "full_name", null: false
    t.datetime "locked_at"
    t.string "phone"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "unconfirmed_email"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["cpf"], name: "index_users_on_cpf", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "addresses", "users"
  add_foreign_key "brindes", "game_of_the_months"
  add_foreign_key "game_of_the_month_products", "game_of_the_months"
  add_foreign_key "game_of_the_month_products", "products"
  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "products", on_delete: :nullify
  add_foreign_key "orders", "users"
  add_foreign_key "payment_webhook_events", "orders"
  add_foreign_key "product_options", "products"
  add_foreign_key "product_photos", "products"
  add_foreign_key "product_tags", "products"
  add_foreign_key "product_tags", "tags"
  add_foreign_key "products", "categories"
  add_foreign_key "questions", "products"
  add_foreign_key "shipment_tracking_events", "shipments"
  add_foreign_key "shipments", "orders"
end
