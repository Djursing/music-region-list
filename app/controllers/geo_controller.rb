# frozen_string_literal: true

# Serves the kommune boundaries to the browser.
#
# The geometry is static and comparatively large (1.7 MB, ~500 KB gzipped), so
# it is deliberately not embedded in the trip page: it is fetched once, cached
# hard, and reused for every trip. Only the small per-trip colour map changes.
class GeoController < ApplicationController
  allow_unauthenticated only: :kommuner

  PATH = Geo::KommuneIndex::GEOJSON_PATH

  def kommuner
    # Boundaries only change when `rake geo:kommuner` is re-run, so the digest
    # of the file is a perfect cache key: browsers revalidate with an ETag and
    # get a 304 rather than re-downloading.
    fresh_when(etag: file_digest, public: true, last_modified: PATH.mtime)
    return if request.fresh?(response)

    expires_in 1.year, public: true
    send_file PATH, type: "application/geo+json", disposition: "inline"
  end

  private

  def file_digest
    Rails.cache.fetch("kommuner-geojson-digest/#{PATH.mtime.to_i}") do
      Digest::SHA256.file(PATH).hexdigest
    end
  end
end
