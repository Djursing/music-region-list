# frozen_string_literal: true

require "test_helper"

class ImportPlaylistJobTest < ActiveSupport::TestCase
  setup do
    @account = spotify_account
    @playlist = @account.playlists.create!(spotify_id: "p1", import_status: "pending")
  end

  def stub_playlist(tracks, name: "Roadtrip")
    stub_spotify(:get, "/playlists/p1", body: {
      "name" => name, "snapshot_id" => "snap1", "owner" => { "display_name" => "Oliver" }
    })
    stub_request(:get, "https://api.spotify.com/v1/playlists/p1/items")
      .with(query: hash_including({}))
      .to_return(status: 200, body: playlist_items_page(tracks).to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  test "extracts every credited artist, features included" do
    stub_playlist([
      spotify_track(id: "t1", name: "Solo", artists: [ { id: "a1", name: "Suspekt" } ]),
      spotify_track(id: "t2", name: "Duet", artists: [ { id: "a1", name: "Suspekt" }, { id: "a2", name: "MØ" } ])
    ])

    ImportPlaylistJob.perform_now(@playlist)
    @playlist.reload

    assert @playlist.imported?
    assert_equal 2, @playlist.track_count
    assert_equal %w[MØ Suspekt], @playlist.artists.order(:name).pluck(:name)
  end

  test "stores a featured track against both artists so either kommune can play it" do
    stub_playlist([
      spotify_track(id: "t2", name: "Duet", artists: [ { id: "a1", name: "Suspekt" }, { id: "a2", name: "MØ" } ])
    ])

    ImportPlaylistJob.perform_now(@playlist)

    assert_equal 2, ArtistTrack.where(track_uri: "spotify:track:t2").count
    assert ArtistTrack.all.all? { |t| t.source == ArtistTrack::PLAYLIST }
  end

  test "counts tracks per artist so features can be spotted on the import screen" do
    stub_playlist([
      spotify_track(id: "t1", name: "A", artists: [ { id: "a1", name: "Suspekt" } ]),
      spotify_track(id: "t2", name: "B", artists: [ { id: "a1", name: "Suspekt" } ]),
      spotify_track(id: "t3", name: "C", artists: [ { id: "a1", name: "Suspekt" }, { id: "a2", name: "Guest" } ])
    ])

    ImportPlaylistJob.perform_now(@playlist)

    counts = @playlist.playlist_artists.includes(:artist).to_h { |pa| [ pa.artist.name, pa.track_count ] }
    assert_equal({ "Suspekt" => 3, "Guest" => 1 }, counts)
  end

  test "is idempotent when the same playlist is imported twice" do
    stub_playlist([ spotify_track(id: "t1", name: "A", artists: [ { id: "a1", name: "Suspekt" } ]) ])

    2.times { ImportPlaylistJob.perform_now(@playlist) }

    assert_equal 1, Artist.count
    assert_equal 1, ArtistTrack.count
    assert_equal 1, @playlist.reload.playlist_artists.count
    assert_equal 1, @playlist.playlist_artists.first.track_count
  end

  test "drops artists that disappeared from a re-imported playlist" do
    stub_playlist([
      spotify_track(id: "t1", name: "A", artists: [ { id: "a1", name: "Suspekt" } ]),
      spotify_track(id: "t2", name: "B", artists: [ { id: "a2", name: "Gone" } ])
    ])
    ImportPlaylistJob.perform_now(@playlist)
    assert_equal 2, @playlist.reload.playlist_artists.count

    WebMock.reset!
    stub_playlist([ spotify_track(id: "t1", name: "A", artists: [ { id: "a1", name: "Suspekt" } ]) ])
    ImportPlaylistJob.perform_now(@playlist)

    assert_equal [ "Suspekt" ], @playlist.reload.artists.pluck(:name)
  end

  test "records an actionable message when the playlist is not the user's own" do
    # Spotify returns metadata with no items array for playlists the user
    # neither owns nor collaborates on, rather than an error status.
    stub_spotify(:get, "/playlists/p1", body: { "name" => "This Is Suspekt" })
    stub_request(:get, "https://api.spotify.com/v1/playlists/p1/items")
      .with(query: hash_including({}))
      .to_return(status: 200, body: { "name" => "This Is Suspekt" }.to_json,
                 headers: { "Content-Type" => "application/json" })

    # Must not re-raise: this can never succeed on retry.
    assert_nothing_raised { ImportPlaylistJob.perform_now(@playlist) }

    @playlist.reload
    assert @playlist.failed?
    assert_match(/own a copy|make your own copy/i, @playlist.import_error)
  end

  test "re-raises transient failures so the job can retry" do
    stub_spotify(:get, "/playlists/p1", status: 500, body: { "error" => { "message" => "server error" } })

    assert_raises(Spotify::Error) { ImportPlaylistJob.perform_now(@playlist) }
    assert @playlist.reload.failed?
  end

  test "ignores episodes and tracks with no credited artist" do
    stub_playlist([
      spotify_track(id: "t1", name: "Real", artists: [ { id: "a1", name: "Suspekt" } ]),
      { "uri" => "spotify:track:t9", "type" => "track", "name" => "Orphan", "artists" => [] }
    ])

    ImportPlaylistJob.perform_now(@playlist)

    assert_equal 1, Artist.count
    assert_equal 2, @playlist.reload.track_count, "orphan still counts as a track on the playlist"
  end
end
