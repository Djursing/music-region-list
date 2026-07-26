# frozen_string_literal: true

# Namespace for the logic that turns a map and a playlist into a drive.
#
# The errors live here rather than beside the class that raises them because
# Zeitwerk derives constant names from filenames: a constant defined in
# trips/zone_assigner.rb has to be Trips::ZoneAssigner.
module Trips
  # Raised when a trip is started before the phone has reported a usable
  # position, so there is no kommune to choose a first track from.
  class NoPositionYet < StandardError; end

  # Raised when the kommune's artist has no playable tracks at all — typically
  # a playlist whose tracks all failed to import.
  class NoTracksAvailable < StandardError; end

  # Raised when an action needs something to be playing and nothing is.
  class NotPlaying < StandardError; end
end
