# frozen_string_literal: true

# Safety net for the driving loop.
#
# QueueNextTrackJob keeps itself alive by scheduling its own next run, which is
# efficient but means a single dropped job would end the music silently. This
# runs every minute from config/recurring.yml and restarts the loop for any
# active trip that has gone quiet.
#
# Solid Queue's recurring scheduler is cron-based, so one minute is the finest
# granularity available — which is precisely why the main loop schedules itself
# instead of relying on this.
class PlaybackWatchdogJob < ApplicationJob
  queue_as :default

  # If a trip has no queue job due within this window, assume the chain broke.
  # Comfortably longer than the loop's own longest sleep.
  STALL_THRESHOLD = 2.minutes

  def perform
    Trip.active.find_each do |trip|
      next if queue_job_pending?(trip)

      Rails.logger.warn("[watchdog] restarting queue loop for trip #{trip.id}")
      QueueNextTrackJob.perform_later(trip)
    end
  end

  private

  # Looks for an unfinished QueueNextTrackJob for this trip, whether it is ready
  # to run or sleeping until its scheduled moment.
  def queue_job_pending?(trip)
    SolidQueue::Job
      .where(class_name: "QueueNextTrackJob", finished_at: nil)
      .where("arguments::text LIKE ?", "%\"_aj_globalid\":\"gid://%/Trip/#{trip.id}\"%")
      .where("scheduled_at IS NULL OR scheduled_at <= ?", STALL_THRESHOLD.from_now)
      .exists?
  end
end
