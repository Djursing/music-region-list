class CreateArtistTracks < ActiveRecord::Migration[8.0]
  def change
    create_table :artist_tracks do |t|
      t.references :artist, null: false, foreign_key: true
      t.references :playlist, foreign_key: true

      t.string :track_uri, null: false
      t.string :track_name
      t.string :album_name
      t.integer :duration_ms

      # "playlist" tracks come from the imported playlist and are played first;
      # "catalog" tracks come from the lazy album crawl and are only reached
      # once the playlist tier is exhausted for that artist.
      t.string :source, null: false

      t.timestamps
    end

    # A track credited to two artists is stored once per artist, so uniqueness
    # is per (artist, track) rather than per track. Playlist import runs before
    # any catalog crawl, so the playlist tier always wins this race.
    add_index :artist_tracks, [ :artist_id, :track_uri ], unique: true
    add_index :artist_tracks, [ :artist_id, :source ]
  end
end
