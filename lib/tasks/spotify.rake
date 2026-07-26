namespace :spotify do
  desc "Write Spotify credentials from SPOTIFY_CLIENT_ID / SPOTIFY_CLIENT_SECRET into encrypted credentials"
  task configure: :environment do
    require "yaml"

    id = ENV["SPOTIFY_CLIENT_ID"].presence
    secret = ENV["SPOTIFY_CLIENT_SECRET"].presence

    if id.nil? && secret.nil?
      abort "Set SPOTIFY_CLIENT_ID and/or SPOTIFY_CLIENT_SECRET. See README."
    end

    store = Rails.application.encrypted("config/credentials.yml.enc", key_path: "config/master.key")
    config = YAML.safe_load(store.read.to_s, permitted_classes: [ Symbol ]) || {}
    config["spotify"] ||= {}
    config["spotify"]["client_id"] = id if id
    config["spotify"]["client_secret"] = secret if secret
    store.write(config.to_yaml)

    # Deliberately reports only whether values are present. The secret must not
    # end up in a terminal buffer, a shell history, or a scrollback log.
    puts "Saved to encrypted credentials:"
    puts "  client_id:     #{id ? "updated (#{id[0, 6]}…)" : 'unchanged'}"
    puts "  client_secret: #{secret ? "updated (#{secret.length} characters)" : 'unchanged'}"
  end

  desc "Check that Spotify credentials work by requesting a token"
  task verify: :environment do
    unless Spotify::OAuth.configured?
      abort "No Spotify credentials found. Run `rake spotify:configure` first."
    end

    require "net/http"

    # Client-credentials grant just proves the id/secret pair is valid; it needs
    # no user and grants no user scopes.
    uri = URI(Spotify::OAuth::TOKEN_URL)
    response = Net::HTTP.post_form(uri, {
      "grant_type" => "client_credentials",
      "client_id" => Spotify::OAuth.client_id,
      "client_secret" => Spotify::OAuth.client_secret
    })

    if response.code == "200"
      puts "Credentials are valid — Spotify issued a token."
      puts "Next: add yourself under User Management in the Spotify dashboard, then sign in at"
      puts "  http://127.0.0.1:3000  (not localhost — the redirect URI must match exactly)"
    else
      body = JSON.parse(response.body) rescue {}
      abort "Spotify rejected the credentials (#{response.code}): " \
            "#{body['error_description'] || body['error'] || response.body}"
    end
  end
end
