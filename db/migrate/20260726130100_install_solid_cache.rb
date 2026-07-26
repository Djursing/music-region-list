# Generated from db/cache_schema.rb.
#
# Rails 8 scaffolds the Solid Cache tables into a dedicated database.
# Railway provides a single Postgres, so they are installed here as ordinary
# migrations against the primary connection instead.
class InstallSolidCache < ActiveRecord::Migration[8.0]
  def change
      create_table "solid_cache_entries" do |t|
        t.binary "key", limit: 1024, null: false
        t.binary "value", limit: 536870912, null: false
        t.datetime "created_at", null: false
        t.integer "key_hash", limit: 8, null: false
        t.integer "byte_size", limit: 4, null: false
        t.index [ "byte_size" ], name: "index_solid_cache_entries_on_byte_size"
        t.index [ "key_hash", "byte_size" ], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
        t.index [ "key_hash" ], name: "index_solid_cache_entries_on_key_hash", unique: true
      end
  end
end
