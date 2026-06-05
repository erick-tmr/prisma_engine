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

  create_table "categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["position"], name: "index_categories_on_position"
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

  create_table "option_types", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_option_types_on_slug", unique: true
  end

  create_table "option_values", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "option_type_id", null: false
    t.integer "position", default: 0, null: false
    t.integer "price_contribution_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["option_type_id", "name"], name: "index_option_values_on_option_type_id_and_name", unique: true
    t.index ["option_type_id"], name: "index_option_values_on_option_type_id"
  end

  create_table "product_option_types", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "option_type_id", null: false
    t.integer "position", default: 0, null: false
    t.bigint "product_id", null: false
    t.datetime "updated_at", null: false
    t.index ["option_type_id"], name: "index_product_option_types_on_option_type_id"
    t.index ["product_id", "option_type_id"], name: "index_product_option_types_on_product_id_and_option_type_id", unique: true
    t.index ["product_id"], name: "index_product_option_types_on_product_id"
  end

  create_table "product_photos", force: :cascade do |t|
    t.string "alt_text"
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.bigint "product_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "variant_id"
    t.index ["product_id"], name: "index_product_photos_on_product_id"
    t.index ["variant_id"], name: "index_product_photos_on_variant_id"
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
    t.string "legacy_short_id"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "price_cents", default: 0, null: false
    t.boolean "published", default: true, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
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

  create_table "tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_tags_on_slug", unique: true
  end

  create_table "variant_option_values", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "option_value_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "variant_id", null: false
    t.index ["option_value_id"], name: "index_variant_option_values_on_option_value_id"
    t.index ["variant_id", "option_value_id"], name: "index_variant_option_values_uniqueness", unique: true
    t.index ["variant_id"], name: "index_variant_option_values_on_variant_id"
  end

  create_table "variants", force: :cascade do |t|
    t.boolean "available", default: true, null: false
    t.datetime "created_at", null: false
    t.boolean "is_master", default: false, null: false
    t.integer "position", default: 0, null: false
    t.integer "price_cents", default: 0, null: false
    t.integer "price_modifier_cents"
    t.bigint "product_id", null: false
    t.string "sku", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_variants_on_product_id"
    t.index ["product_id"], name: "index_variants_one_master_per_product", unique: true, where: "(is_master = true)"
    t.index ["sku"], name: "index_variants_on_sku", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "option_values", "option_types"
  add_foreign_key "product_option_types", "option_types"
  add_foreign_key "product_option_types", "products"
  add_foreign_key "product_photos", "products"
  add_foreign_key "product_photos", "variants"
  add_foreign_key "product_tags", "products"
  add_foreign_key "product_tags", "tags"
  add_foreign_key "products", "categories"
  add_foreign_key "questions", "products"
  add_foreign_key "shipment_tracking_events", "shipments"
  add_foreign_key "variant_option_values", "option_values"
  add_foreign_key "variant_option_values", "variants"
  add_foreign_key "variants", "products"
end
