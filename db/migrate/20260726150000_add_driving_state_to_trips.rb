class AddDrivingStateToTrips < ActiveRecord::Migration[8.0]
  def change
    change_table :trips, bulk: true do |t|
      # When playback stopped. The loop keeps checking back for a while — a
      # pause at a services stop shouldn't end the trip — but gives up
      # eventually so a forgotten trip doesn't poll Spotify indefinitely.
      t.datetime :idle_since

      # Whether the kommune was decided from a real GPS fix or projected from
      # the last one, so the HUD can be honest about it.
      t.string :position_source

      # Last thing that went wrong, shown in the HUD. Cleared on success.
      t.text :last_error
    end
  end
end
