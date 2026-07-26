class CreateTripPlays < ActiveRecord::Migration[8.0]
  def change
    create_table :trip_plays do |t|
      t.references :trip, null: false, foreign_key: true
      t.references :artist, null: false, foreign_key: true
      t.references :artist_track, null: false, foreign_key: true

      t.string :kommune_kode, limit: 4
      t.datetime :queued_at, null: false

      t.timestamps
    end

    # Exhaustion is tracked per (trip, artist) rather than per zone: an artist
    # re-used across two kommuner shares one pool, so you never hear the same
    # song twice in a single drive.
    add_index :trip_plays, [ :trip_id, :artist_id ]
    add_index :trip_plays, [ :trip_id, :artist_track_id ], unique: true
  end
end
