# frozen_string_literal: true

# Fetches an artist's wider catalogue so a kommune has something to play once
# its playlist tracks are used up.
#
# Deliberately lazy. An artist with twenty albums costs a couple of dozen API
# calls, and most trips never exhaust an artist's playlist tracks at all, so
# doing this up front for every artist on a playlist would be mostly wasted
# work against a rate-limited API.
#
# `Get Artist's Top Tracks` was removed in February 2026, so there is no short
# cut: the catalogue has to be walked album by album.
class CrawlCatalogJob < ApplicationJob
  queue_as :low

  limits_concurrency to: 1, key: ->(artist) { artist.id }

  # Compilations and appearances are excluded: they are mostly duplicates of
  # tracks already covered, and "appears_on" drags in other artists' records.
  INCLUDE_GROUPS = "album,single"

  # Cap on the search fallback. Enough to keep a kommune varied for a long
  # drive without walking an entire discography one small page at a time.
  SEARCH_LIMIT = 50

  def perform(artist, account: nil)
    return if artist.catalog_synced?

    account ||= SpotifyAccount.order(:id).first
    return if account.nil?

    client = account.client
    seen, stored = crawl_albums(client, artist)

    # Spotify sometimes holds more than one artist entity under the same name,
    # and a playlist can credit one that has no releases attached — its /albums
    # is genuinely empty while the artist obviously has a catalogue. Searching
    # by name picks the records up regardless of which entity they hang off.
    #
    # The trigger is having seen no tracks at all, not having stored none: an
    # artist whose albums hold only songs already known from the playlist has a
    # perfectly good catalogue and needs no fallback.
    stored += crawl_by_name(client, artist) if seen.zero?

    artist.update!(catalog_synced_at: Time.current)
    Rails.logger.info("[catalog] #{artist.name}: saw #{seen} album tracks, stored #{stored}")
  rescue Spotify::RateLimited => e
    self.class.set(wait: (e.retry_after || 30).seconds).perform_later(artist, account: account)
  rescue Spotify::ReauthorizationRequired
    # Nothing to do until the driver reconnects; the queue loop will surface it.
    nil
  end

  private

  # Returns [tracks seen, tracks newly stored].
  def crawl_albums(client, artist)
    seen = 0
    stored = 0

    client.artist_albums(artist.spotify_id, include_groups: INCLUDE_GROUPS).each do |album|
      client.album_tracks(album["id"]).each do |track|
        # An album can credit several artists; only keep tracks this artist is
        # actually on, or a compilation would pollute their pool.
        next unless track["artists"].to_a.any? { |a| a["id"] == artist.spotify_id }

        seen += 1
        stored += 1 if store(artist, track, album["name"])
      end
    end

    [ seen, stored ]
  end

  def crawl_by_name(client, artist)
    stored = 0

    client.search_tracks(artist.name, max: SEARCH_LIMIT).each do |track|
      # Match on name rather than id, since the whole reason for this path is
      # that the id on the playlist is not the one the releases are filed under.
      next unless track["artists"].to_a.any? { |a| a["name"].to_s.casecmp?(artist.name) }

      stored += 1 if store(artist, track, track.dig("album", "name"))
    end

    stored
  end

  def store(artist, track, album_name)
    return false if track["uri"].blank?

    record = ArtistTrack.find_or_initialize_by(artist_id: artist.id, track_uri: track["uri"])

    # Never demote a playlist track to catalogue: the driver picked it, so it
    # keeps its place at the front of the queue.
    return false if record.persisted? && record.source == ArtistTrack::PLAYLIST

    record.source = ArtistTrack::CATALOG
    record.track_name = track["name"]
    record.album_name = album_name
    record.duration_ms = track["duration_ms"]
    record.save!
    true
  end
end
