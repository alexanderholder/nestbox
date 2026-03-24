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

ActiveRecord::Schema[8.1].define(version: 2026_03_24_062542) do
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

  create_table "cameras", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "device_type"
    t.datetime "last_synced_at"
    t.string "name", null: false
    t.string "nest_id", null: false
    t.datetime "updated_at", null: false
    t.index ["nest_id"], name: "index_cameras_on_nest_id", unique: true
  end

  create_table "events", force: :cascade do |t|
    t.integer "camera_id", null: false
    t.text "clip_preview_url"
    t.string "clip_url"
    t.datetime "created_at", null: false
    t.string "download_state", default: "pending"
    t.datetime "downloaded_at"
    t.integer "duration_seconds"
    t.datetime "end_time"
    t.string "event_session_id"
    t.string "event_type", null: false
    t.string "nest_id", null: false
    t.datetime "start_time", null: false
    t.datetime "updated_at", null: false
    t.index ["camera_id", "start_time"], name: "index_events_on_camera_id_and_start_time"
    t.index ["camera_id"], name: "index_events_on_camera_id"
    t.index ["download_state"], name: "index_events_on_download_state"
    t.index ["event_session_id"], name: "index_events_on_event_session_id"
    t.index ["nest_id"], name: "index_events_on_nest_id", unique: true
  end

  create_table "nest_connection_statuses", force: :cascade do |t|
    t.text "access_token"
    t.datetime "created_at", null: false
    t.text "last_error"
    t.datetime "last_failure_at"
    t.datetime "last_success_at"
    t.string "project_id"
    t.string "pubsub_mode", default: "pull", null: false
    t.text "refresh_token"
    t.string "state", default: "unknown", null: false
    t.datetime "token_expires_at"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "events", "cameras"
end
