class CreatePlaylistArtists < ActiveRecord::Migration[8.0]
  def change
    create_table :playlist_artists do |t|
      t.references :playlist, null: false, foreign_key: true
      t.references :artist, null: false, foreign_key: true

      # How many tracks on this playlist credit the artist. Drives the ordering
      # on the import screen: a one-track credit is usually a guest feature the
      # user would rather not hand a whole kommune to.
      t.integer :track_count, default: 0, null: false

      # Set from the import screen. Excluded artists stay in the database (their
      # tracks are still credited to them) but are left out of the pool when a
      # trip deals artists across the map.
      t.boolean :excluded, default: false, null: false

      t.timestamps
    end

    add_index :playlist_artists, [ :playlist_id, :artist_id ], unique: true
    add_index :playlist_artists, [ :playlist_id, :excluded ]
  end
end
