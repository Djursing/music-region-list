# frozen_string_literal: true

# Fetches an artist's wider catalogue so a kommune has something to play once
# its playlist tracks are used up.
#
# Deliberately lazy. An artist with twenty albums costs about twenty-two API
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

  def perform(artist, account: nil)
    return if artist.catalog_synced?

    account ||= SpotifyAccount.order(:id).first
    return if account.nil?

    client = account.client
    stored = 0

    client.artist_albums(artist.spotify_id, include_groups: INCLUDE_GROUPS).each do |album|
      client.album_tracks(album["id"]).each do |track|
        # An album can credit several artists; only keep tracks this artist is
        # actually on, or a compilation would pollute their pool.
        next unless track["artists"].to_a.any? { |a| a["id"] == artist.spotify_id }
        next if track["uri"].blank?

        record = ArtistTrack.find_or_initialize_by(artist_id: artist.id, track_uri: track["uri"])

        # Never demote a playlist track to catalogue: the driver picked it, so
        # it keeps its place at the front of the queue.
        next if record.persisted? && record.source == ArtistTrack::PLAYLIST

        record.source = ArtistTrack::CATALOG
        record.track_name = track["name"]
        record.album_name = album["name"]
        record.duration_ms = track["duration_ms"]
        record.save!
        stored += 1
      end
    end

    artist.update!(catalog_synced_at: Time.current)
    Rails.logger.info("[catalog] #{artist.name}: stored #{stored} tracks")
  rescue Spotify::RateLimited => e
    self.class.set(wait: (e.retry_after || 30).seconds).perform_later(artist, account: account)
  rescue Spotify::ReauthorizationRequired
    # Nothing to do until the driver reconnects; the queue loop will surface it.
    nil
  end
end
