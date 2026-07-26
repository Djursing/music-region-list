class CreateSpotifyAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :spotify_accounts do |t|
      t.string :spotify_user_id, null: false
      t.string :display_name

      # Stored via ActiveRecord::Encryption (see SpotifyAccount#encrypts), so
      # these hold ciphertext and need more room than the raw tokens.
      t.text :access_token
      t.text :refresh_token
      t.datetime :access_token_expires_at

      # Spotify began expiring refresh tokens six months after the original
      # authorisation in June 2026. We record when the user actually authorised
      # so the UI can warn before the token dies mid-roadtrip.
      t.datetime :authorized_at

      t.timestamps
    end

    add_index :spotify_accounts, :spotify_user_id, unique: true
  end
end
