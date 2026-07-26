class CreateTripLocations < ActiveRecord::Migration[8.0]
  def change
    create_table :trip_locations do |t|
      t.references :trip, null: false, foreign_key: true

      t.decimal :latitude, precision: 9, scale: 6, null: false
      t.decimal :longitude, precision: 9, scale: 6, null: false

      # Straight from the browser Geolocation API. speed is metres/second and
      # heading is degrees clockwise from true north; both are null when the
      # device cannot determine them (typically when stationary).
      t.float :speed
      t.float :heading
      t.float :accuracy

      t.datetime :recorded_at, null: false

      t.timestamps
    end

    add_index :trip_locations, [ :trip_id, :recorded_at ]
  end
end
