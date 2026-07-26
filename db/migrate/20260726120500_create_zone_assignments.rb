class CreateZoneAssignments < ActiveRecord::Migration[8.0]
  def change
    create_table :zone_assignments do |t|
      t.references :trip, null: false, foreign_key: true
      t.references :artist, null: false, foreign_key: true

      # DAWA kommune code, e.g. "0101" for Kobenhavn. Four digits including a
      # leading zero, so it is a string rather than an integer.
      t.string :kommune_kode, null: false, limit: 4

      t.timestamps
    end

    add_index :zone_assignments, [ :trip_id, :kommune_kode ], unique: true
  end
end
