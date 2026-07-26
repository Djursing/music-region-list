# frozen_string_literal: true

# The driving loop: keeps Spotify's queue one track ahead of what's playing,
# choosing each track from whichever kommune the car is in.
#
# This does not poll on a timer. Spotify tells us exactly how much of the
# current track remains, so the job schedules *itself* for the moment it is
# needed and sleeps until then. Over a four-hour drive that is roughly 120 calls
# rather than the ~1,400 a ten-second poll would make — which matters for rate
# limits, and for the phone's battery and data allowance.
#
# Queueing happens late on purpose. Spotify has no "remove from queue"
# operation, so committing as close to the track change as is safe maximises the
# chance the choice reflects where the car actually is.
class QueueNextTrackJob < ApplicationJob
  queue_as :default

  # How far before the end of the current track to queue the next one. Long
  # enough that Spotify has it ready for a gapless change, short enough that a
  # border crossed a minute ago is still reflected.
  QUEUE_LEAD = 25.seconds

  # A little past the track change, so the next run sees the new track rather
  # than racing the one that just ended.
  POST_CHANGE_DELAY = 3.seconds

  # Nothing is playing. Spotify may simply be paused at a services stop, so keep
  # checking back rather than ending the trip.
  IDLE_RECHECK = 45.seconds

  # Give up waiting for playback to resume after this, so a trip left running
  # overnight doesn't poll Spotify until the token expires.
  IDLE_TIMEOUT = 30.minutes

  # Only one run per trip at a time. Two overlapping runs would each queue a
  # track and, with no way to un-queue, the mistake would be audible.
  limits_concurrency to: 1, key: ->(trip) { trip.id }

  def perform(trip)
    return unless trip.reload.active?

    state = trip.spotify_account.client.playback_state

    if state.nil? || state["is_playing"] != true
      handle_idle(trip)
      return
    end

    trip.update!(idle_since: nil) if trip.idle_since?

    remaining = remaining_ms(state)
    return reschedule(trip, IDLE_RECHECK) if remaining.nil?

    current_uri = state.dig("item", "uri")

    if remaining > QUEUE_LEAD.in_milliseconds
      # Too early — come back just before this track ends.
      reschedule(trip, ((remaining - QUEUE_LEAD.in_milliseconds) / 1000.0).seconds)
    elsif trip.queued_for_track_uri == current_uri
      # Already queued something to follow this track. Wait for the change.
      reschedule(trip, ((remaining / 1000.0) + POST_CHANGE_DELAY).seconds)
    else
      queue_next(trip, current_uri)
      reschedule(trip, ((remaining / 1000.0) + POST_CHANGE_DELAY).seconds)
    end
  rescue Spotify::NoActiveDevice
    # Spotify dropped off Connect — usually the phone went to sleep hard. Keep
    # checking; the driver will notice the music stopped before we do.
    trip.update!(last_error: "No active Spotify device")
    handle_idle(trip)
  rescue Spotify::RateLimited => e
    reschedule(trip, (e.retry_after || 5).seconds)
  rescue Spotify::PremiumRequired => e
    # Not recoverable by retrying, and the driver needs to know.
    trip.update!(status: Trip::FINISHED, ended_at: Time.current, last_error: e.message)
    trip.broadcast_hud
  end

  private

  def remaining_ms(state)
    duration = state.dig("item", "duration_ms")
    progress = state["progress_ms"]
    return nil if duration.nil? || progress.nil?

    [ duration - progress, 0 ].max
  end

  def queue_next(trip, current_uri)
    position = Trips::PositionResolver.new(trip).call
    kommune = position&.kommune

    # No usable position: hold the kommune we last knew rather than skipping a
    # track, so the music keeps going while the phone is locked.
    kode = kommune&.kode || trip.current_kommune_kode
    return reschedule(trip, IDLE_RECHECK) if kode.nil?

    artist = trip.artist_for(kode)
    chooser = Trips::TrackChooser.new(trip, artist)
    choice = chooser.call
    return reschedule(trip, IDLE_RECHECK) if choice.nil?

    trip.spotify_account.client.enqueue(choice.track.track_uri)

    trip.trip_plays.create!(
      artist: artist,
      artist_track: choice.track,
      kommune_kode: kode,
      queued_at: Time.current
    ) unless choice.repeat?

    trip.update!(
      current_kommune_kode: kode,
      queued_for_track_uri: current_uri,
      last_queued_track_uri: choice.track.track_uri,
      position_source: position&.source&.to_s,
      last_error: nil
    )

    # Widen this artist's pool in the background so the next visit to one of
    # their kommuner has more than a repeat to offer.
    CrawlCatalogJob.perform_later(artist) if chooser.needs_catalog?

    trip.broadcast_hud
  end

  def handle_idle(trip)
    trip.update!(idle_since: Time.current) unless trip.idle_since?

    if trip.idle_since < IDLE_TIMEOUT.ago
      trip.update!(status: Trip::FINISHED, ended_at: Time.current)
      trip.broadcast_hud
      return
    end

    trip.broadcast_hud
    reschedule(trip, IDLE_RECHECK)
  end

  def reschedule(trip, delay)
    self.class.set(wait: delay).perform_later(trip)
  end
end
