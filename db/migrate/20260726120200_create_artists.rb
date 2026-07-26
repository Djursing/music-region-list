class CreateArtists < ActiveRecord::Migration[8.0]
  def change
    create_table :artists do |t|
      t.string :spotify_id, null: false
      t.string :name, null: false
      t.string :image_url

      # Null until the artist's wider catalogue has been crawled. The crawl is
      # lazy — it only happens once a zone exhausts the artist's playlist
      # tracks — so most artists carry null here for the whole trip.
      t.datetime :catalog_synced_at

      t.timestamps
    end

    add_index :artists, :spotify_id, unique: true
  end
end
