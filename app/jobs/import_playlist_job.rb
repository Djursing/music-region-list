# frozen_string_literal: true

# Reads a Spotify playlist and turns it into the artist pool for a trip.
#
# Every artist credited on a track counts, features included, because a feature
# is still a legitimate artist to hand a kommune to. The import screen then lets
# the user drop the ones they don't want, which is easier to judge with the
# track counts in front of them than to guess at here.
class ImportPlaylistJob < ApplicationJob
  queue_as :default

  # Importing the same playlist twice concurrently would double-count tracks.
  limits_concurrency to: 1, key: ->(playlist) { playlist.id }

  def perform(playlist)
    playlist.update!(import_status: "importing", import_error: nil)

    client = playlist.spotify_account.client
    metadata = client.playlist(playlist.spotify_id)

    playlist.assign_attributes(
      name: metadata["name"],
      owner_name: metadata.dig("owner", "display_name"),
      snapshot_id: metadata["snapshot_id"]
    )

    track_counts = Hash.new(0)
    total_tracks = 0

    client.playlist_items(playlist.spotify_id) do |track|
      next if track["uri"].blank?

      total_tracks += 1
      credited = track["artists"].to_a.select { |a| a["id"].present? }
      next if credited.empty?

      credited.each do |payload|
        artist = Artist.upsert_from_spotify!(payload)
        store_track(artist, playlist, track)
        track_counts[artist.id] += 1
      end
    end

    persist_artist_counts(playlist, track_counts)

    playlist.update!(
      import_status: "imported",
      track_count: total_tracks,
      imported_at: Time.current
    )
    broadcast(playlist)
  rescue Spotify::PlaylistNotAccessible, Spotify::ReauthorizationRequired, Spotify::Error => e
    # These are all conditions the user can act on — a playlist they don't own,
    # an expired authorisation, a network failure — so the message is stored for
    # display rather than swallowed into a retry loop.
    playlist.update!(import_status: "failed", import_error: e.message)
    broadcast(playlist)

    # PlaylistNotAccessible is a permanent state of the world, not a transient
    # failure, so re-raising would only burn retries on something that can never
    # succeed. Everything else is worth another attempt.
    raise unless e.is_a?(Spotify::PlaylistNotAccessible)
  end

  private

  def broadcast(playlist)
    Turbo::StreamsChannel.broadcast_replace_to(
      playlist,
      target: ActionView::RecordIdentifier.dom_id(playlist),
      partial: "playlists/details",
      locals: { playlist: playlist }
    )
  end

  def store_track(artist, playlist, track)
    record = ArtistTrack.find_or_initialize_by(artist_id: artist.id, track_uri: track["uri"])

    # A track already known from a catalogue crawl gets promoted to the playlist
    # tier: the user explicitly chose it, so it should play before deep cuts.
    record.source = ArtistTrack::PLAYLIST
    record.playlist_id = playlist.id
    record.track_name = track["name"]
    record.album_name = track.dig("album", "name")
    record.duration_ms = track["duration_ms"]
    record.save!
  end

  def persist_artist_counts(playlist, track_counts)
    track_counts.each do |artist_id, count|
      link = PlaylistArtist.find_or_initialize_by(playlist_id: playlist.id, artist_id: artist_id)
      link.track_count = count
      link.save!
    end

    # A re-import of a changed playlist may have dropped artists entirely.
    playlist.playlist_artists.where.not(artist_id: track_counts.keys).destroy_all
  end
end
