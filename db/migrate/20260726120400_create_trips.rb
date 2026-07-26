class CreateTrips < ActiveRecord::Migration[8.0]
  def change
    create_table :trips do |t|
      t.references :spotify_account, null: false, foreign_key: true
      t.references :playlist, null: false, foreign_key: true

      t.string :name
      t.string :status, default: "draft", null: false
      t.datetime :started_at
      t.datetime :ended_at

      # Denormalised so the HUD can render without re-running a point-in-polygon
      # lookup, and so we can detect a border crossing by comparing against the
      # freshly resolved kommune.
      t.string :current_kommune_kode

      # The track we have already pushed into Spotify's queue. Used to avoid
      # queueing twice for the same playing track — Spotify has no
      # "remove from queue" API, so a double-queue is unrecoverable.
      t.string :queued_for_track_uri
      t.string :last_queued_track_uri

      t.timestamps
    end

    add_index :trips, [ :spotify_account_id, :status ]
  end
end
