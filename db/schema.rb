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

ActiveRecord::Schema[8.0].define(version: 2026_07_26_140000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "artist_tracks", force: :cascade do |t|
    t.bigint "artist_id", null: false
    t.bigint "playlist_id"
    t.string "track_uri", null: false
    t.string "track_name"
    t.string "album_name"
    t.integer "duration_ms"
    t.string "source", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["artist_id", "source"], name: "index_artist_tracks_on_artist_id_and_source"
    t.index ["artist_id", "track_uri"], name: "index_artist_tracks_on_artist_id_and_track_uri", unique: true
    t.index ["artist_id"], name: "index_artist_tracks_on_artist_id"
    t.index ["playlist_id"], name: "index_artist_tracks_on_playlist_id"
  end

  create_table "artists", force: :cascade do |t|
    t.string "spotify_id", null: false
    t.string "name", null: false
    t.string "image_url"
    t.datetime "catalog_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["spotify_id"], name: "index_artists_on_spotify_id", unique: true
  end

  create_table "playlist_artists", force: :cascade do |t|
    t.bigint "playlist_id", null: false
    t.bigint "artist_id", null: false
    t.integer "track_count", default: 0, null: false
    t.boolean "excluded", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["artist_id"], name: "index_playlist_artists_on_artist_id"
    t.index ["playlist_id", "artist_id"], name: "index_playlist_artists_on_playlist_id_and_artist_id", unique: true
    t.index ["playlist_id", "excluded"], name: "index_playlist_artists_on_playlist_id_and_excluded"
    t.index ["playlist_id"], name: "index_playlist_artists_on_playlist_id"
  end

  create_table "playlists", force: :cascade do |t|
    t.bigint "spotify_account_id", null: false
    t.string "spotify_id", null: false
    t.string "name"
    t.string "owner_name"
    t.string "snapshot_id"
    t.integer "track_count", default: 0, null: false
    t.datetime "imported_at"
    t.string "import_status", default: "pending", null: false
    t.text "import_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["spotify_account_id", "spotify_id"], name: "index_playlists_on_spotify_account_id_and_spotify_id", unique: true
    t.index ["spotify_account_id"], name: "index_playlists_on_spotify_account_id"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.binary "payload", null: false
    t.datetime "created_at", null: false
    t.bigint "channel_hash", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.binary "key", null: false
    t.binary "value", null: false
    t.datetime "created_at", null: false
    t.bigint "key_hash", null: false
    t.integer "byte_size", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "spotify_accounts", force: :cascade do |t|
    t.string "spotify_user_id", null: false
    t.string "display_name"
    t.text "access_token"
    t.text "refresh_token"
    t.datetime "access_token_expires_at"
    t.datetime "authorized_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["spotify_user_id"], name: "index_spotify_accounts_on_spotify_user_id", unique: true
  end

  create_table "trip_locations", force: :cascade do |t|
    t.bigint "trip_id", null: false
    t.decimal "latitude", precision: 9, scale: 6, null: false
    t.decimal "longitude", precision: 9, scale: 6, null: false
    t.float "speed"
    t.float "heading"
    t.float "accuracy"
    t.datetime "recorded_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["trip_id", "recorded_at"], name: "index_trip_locations_on_trip_id_and_recorded_at"
    t.index ["trip_id"], name: "index_trip_locations_on_trip_id"
  end

  create_table "trip_plays", force: :cascade do |t|
    t.bigint "trip_id", null: false
    t.bigint "artist_id", null: false
    t.bigint "artist_track_id", null: false
    t.string "kommune_kode", limit: 4
    t.datetime "queued_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["artist_id"], name: "index_trip_plays_on_artist_id"
    t.index ["artist_track_id"], name: "index_trip_plays_on_artist_track_id"
    t.index ["trip_id", "artist_id"], name: "index_trip_plays_on_trip_id_and_artist_id"
    t.index ["trip_id", "artist_track_id"], name: "index_trip_plays_on_trip_id_and_artist_track_id", unique: true
    t.index ["trip_id"], name: "index_trip_plays_on_trip_id"
  end

  create_table "trips", force: :cascade do |t|
    t.bigint "spotify_account_id", null: false
    t.bigint "playlist_id", null: false
    t.string "name"
    t.string "status", default: "draft", null: false
    t.datetime "started_at"
    t.datetime "ended_at"
    t.string "current_kommune_kode"
    t.string "queued_for_track_uri"
    t.string "last_queued_track_uri"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["playlist_id"], name: "index_trips_on_playlist_id"
    t.index ["spotify_account_id", "status"], name: "index_trips_on_spotify_account_id_and_status"
    t.index ["spotify_account_id"], name: "index_trips_on_spotify_account_id"
  end

  create_table "zone_assignments", force: :cascade do |t|
    t.bigint "trip_id", null: false
    t.bigint "artist_id", null: false
    t.string "kommune_kode", limit: 4, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["artist_id"], name: "index_zone_assignments_on_artist_id"
    t.index ["trip_id", "kommune_kode"], name: "index_zone_assignments_on_trip_id_and_kommune_kode", unique: true
    t.index ["trip_id"], name: "index_zone_assignments_on_trip_id"
  end

  add_foreign_key "artist_tracks", "artists"
  add_foreign_key "artist_tracks", "playlists"
  add_foreign_key "playlist_artists", "artists"
  add_foreign_key "playlist_artists", "playlists"
  add_foreign_key "playlists", "spotify_accounts"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "trip_locations", "trips"
  add_foreign_key "trip_plays", "artist_tracks"
  add_foreign_key "trip_plays", "artists"
  add_foreign_key "trip_plays", "trips"
  add_foreign_key "trips", "playlists"
  add_foreign_key "trips", "spotify_accounts"
  add_foreign_key "zone_assignments", "artists"
  add_foreign_key "zone_assignments", "trips"
end
