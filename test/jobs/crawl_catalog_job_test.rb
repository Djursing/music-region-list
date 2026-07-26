# frozen_string_literal: true

require "test_helper"

class CrawlCatalogJobTest < ActiveSupport::TestCase
  setup do
    @account = spotify_account
    @artist = Artist.create!(spotify_id: "a1", name: "Suspekt")
  end

  def stub_catalog(albums:, tracks_by_album:)
    stub_request(:get, "https://api.spotify.com/v1/artists/a1/albums")
      .with(query: hash_including({}))
      .to_return(status: 200, body: { "items" => albums, "next" => nil }.to_json,
                 headers: { "Content-Type" => "application/json" })

    tracks_by_album.each do |album_id, tracks|
      stub_request(:get, "https://api.spotify.com/v1/albums/#{album_id}/tracks")
        .with(query: hash_including({}))
        .to_return(status: 200, body: { "items" => tracks, "next" => nil }.to_json,
                   headers: { "Content-Type" => "application/json" })
    end
  end

  def catalog_track(id, artist_ids: [ "a1" ])
    { "id" => id, "uri" => "spotify:track:#{id}", "name" => "Track #{id}",
      "duration_ms" => 200_000, "artists" => artist_ids.map { |a| { "id" => a } } }
  end

  test "stores the artist's catalogue and marks it synced" do
    stub_catalog(
      albums: [ { "id" => "alb1", "name" => "First" }, { "id" => "alb2", "name" => "Second" } ],
      tracks_by_album: { "alb1" => [ catalog_track("t1") ], "alb2" => [ catalog_track("t2") ] }
    )

    CrawlCatalogJob.perform_now(@artist, account: @account)

    assert_equal 2, @artist.artist_tracks.from_catalog.count
    assert_equal "First", @artist.artist_tracks.find_by(track_uri: "spotify:track:t1").album_name
    assert @artist.reload.catalog_synced?
  end

  test "skips tracks the artist is not actually on" do
    # A compilation album can list tracks by other artists entirely.
    stub_catalog(
      albums: [ { "id" => "alb1", "name" => "Compilation" } ],
      tracks_by_album: { "alb1" => [ catalog_track("mine"), catalog_track("theirs", artist_ids: [ "other" ]) ] }
    )

    CrawlCatalogJob.perform_now(@artist, account: @account)

    assert_equal [ "spotify:track:mine" ], @artist.artist_tracks.pluck(:track_uri)
  end

  test "never demotes a playlist track to the catalogue tier" do
    # The driver picked this track, so it must keep its place ahead of deep cuts.
    playlist = @account.playlists.create!(spotify_id: "p1", import_status: "imported")
    chosen = ArtistTrack.create!(artist: @artist, playlist: playlist, track_uri: "spotify:track:t1",
                                 track_name: "Chosen", source: ArtistTrack::PLAYLIST)

    stub_catalog(albums: [ { "id" => "alb1", "name" => "Album" } ],
                 tracks_by_album: { "alb1" => [ catalog_track("t1") ] })

    CrawlCatalogJob.perform_now(@artist, account: @account)

    assert_equal ArtistTrack::PLAYLIST, chosen.reload.source
    assert_equal "Chosen", chosen.track_name
  end

  test "does nothing when the catalogue is already synced" do
    @artist.update!(catalog_synced_at: Time.current)

    CrawlCatalogJob.perform_now(@artist, account: @account)

    assert_equal 0, @artist.artist_tracks.count
    # No stubs registered, so any HTTP call would have raised.
  end

  test "falls back to searching by name when the artist has no albums" do
    # Spotify can hold several artist entities under one name, and a playlist
    # may credit one with no releases attached — its /albums is genuinely empty
    # while the artist plainly has a catalogue. Searching by name finds the
    # records regardless of which entity they are filed under.
    stub_catalog(albums: [], tracks_by_album: {})

    stub_request(:get, "https://api.spotify.com/v1/search")
      .with(query: hash_including({ "type" => "track" }))
      .to_return(status: 200, body: { "tracks" => { "items" => [
        { "uri" => "spotify:track:hit", "name" => "Dubai Drip", "duration_ms" => 143_000,
          "album" => { "name" => "Dubai Drip" },
          # A different id for the same artist name — the crux of the problem.
          "artists" => [ { "id" => "some-other-id", "name" => "Suspekt" } ] }
      ] } }.to_json, headers: { "Content-Type" => "application/json" })

    CrawlCatalogJob.perform_now(@artist, account: @account)

    assert_equal [ "spotify:track:hit" ], @artist.artist_tracks.pluck(:track_uri)
    assert @artist.reload.catalog_synced?
  end

  test "the name fallback ignores tracks by a genuinely different artist" do
    stub_catalog(albums: [], tracks_by_album: {})
    stub_request(:get, "https://api.spotify.com/v1/search")
      .with(query: hash_including({ "type" => "track" }))
      .to_return(status: 200, body: { "tracks" => { "items" => [
        { "uri" => "spotify:track:theirs", "name" => "Not Ours", "duration_ms" => 100_000,
          "album" => { "name" => "Other" }, "artists" => [ { "id" => "x", "name" => "Someone Else" } ] }
      ] } }.to_json, headers: { "Content-Type" => "application/json" })

    CrawlCatalogJob.perform_now(@artist, account: @account)

    assert_equal 0, @artist.artist_tracks.count
  end

  test "does not search when the albums crawl already found tracks" do
    # No search stub is registered, so any search request would raise.
    stub_catalog(albums: [ { "id" => "alb1", "name" => "Album" } ],
                 tracks_by_album: { "alb1" => [ catalog_track("t1") ] })

    CrawlCatalogJob.perform_now(@artist, account: @account)

    assert_equal 1, @artist.artist_tracks.count
  end

  test "does not search when the albums hold only tracks already known" do
    # The fallback exists for artists with no releases at all. An artist whose
    # albums contain only songs already imported from the playlist has a
    # perfectly good catalogue, so searching would be wasted calls — and no
    # search stub is registered, so attempting one would raise.
    playlist = @account.playlists.create!(spotify_id: "p1", import_status: "imported")
    ArtistTrack.create!(artist: @artist, playlist: playlist, track_uri: "spotify:track:t1",
                        track_name: "Known", source: ArtistTrack::PLAYLIST)

    stub_catalog(albums: [ { "id" => "alb1", "name" => "Album" } ],
                 tracks_by_album: { "alb1" => [ catalog_track("t1") ] })

    CrawlCatalogJob.perform_now(@artist, account: @account)

    assert_equal 1, @artist.artist_tracks.count
    assert_equal ArtistTrack::PLAYLIST, @artist.artist_tracks.sole.source
  end

  test "retries later when rate limited rather than losing the crawl" do
    stub_request(:get, "https://api.spotify.com/v1/artists/a1/albums")
      .with(query: hash_including({}))
      .to_return(status: 429, headers: { "Retry-After" => "9" })

    assert_enqueued_with(job: CrawlCatalogJob) do
      CrawlCatalogJob.perform_now(@artist, account: @account)
    end

    refute @artist.reload.catalog_synced?, "must not claim success after backing off"
  end
end
