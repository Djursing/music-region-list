class CreatePlaylists < ActiveRecord::Migration[8.0]
  def change
    create_table :playlists do |t|
      t.references :spotify_account, null: false, foreign_key: true
      t.string :spotify_id, null: false
      t.string :name
      t.string :owner_name

      # Spotify's opaque version marker for the playlist. Comparing it on
      # re-import tells us whether the contents changed without refetching
      # every page.
      t.string :snapshot_id

      t.integer :track_count, default: 0, null: false
      t.datetime :imported_at
      t.string :import_status, default: "pending", null: false
      t.text :import_error

      t.timestamps
    end

    add_index :playlists, [ :spotify_account_id, :spotify_id ], unique: true
  end
end
