namespace :geo do
  RAW_URL = "https://api.dataforsyningen.dk/kommuner?format=geojson".freeze
  OUTPUT = Rails.root.join("lib/geo/kommuner.geojson")

  # Retained-point percentage handed to mapshaper's Visvalingam simplifier.
  #
  # Measured against the full-resolution source over 3,000 random points on
  # Danish soil (see the accuracy harness in the commit that introduced this):
  #
  #   1%  -> 1.14 MB, 99.50% correct
  #   3%  -> 1.77 MB, 99.90% correct   <- chosen
  #   8%  -> 3.28 MB, 99.97% correct
  #
  # Every disagreement at 3% is between *adjacent* kommuner, i.e. the boundary
  # sits a few hundred metres off. For this app that means the music changes
  # marginally early or late, which nobody in the car will notice. Not worth
  # doubling the payload for.
  SIMPLIFY_PCT = 3

  # Islands below this area (m^2) are dropped. The raw data models every skerry
  # and breakwater — 1,378 of them — which bloats the file without adding
  # anywhere you can drive to. Samso (114 km2) and friends are far above this.
  MIN_ISLAND_AREA = 500_000

  desc "Fetch Danish kommune boundaries from DAWA and simplify them for lib/geo"
  task kommuner: :environment do
    require "open-uri"
    require "tmpdir"

    Dir.mktmpdir do |dir|
      raw = File.join(dir, "raw.geojson")

      puts "Fetching #{RAW_URL} (~119 MB, takes ~30s)..."
      URI.parse(RAW_URL).open(read_timeout: 300) { |io| IO.copy_stream(io, raw) }
      puts "  downloaded #{(File.size(raw) / 1e6).round(1)} MB"

      # `kode` 0411 is Christianso, which carries udenforkommuneinddeling=true:
      # it is a fortress island administered directly by the Ministry of Defence
      # and belongs to no kommune. Excluding it keeps us at exactly 98 zones.
      # mapshaper is pinned in package.json devDependencies so regenerating the
      # boundaries years from now produces the same simplification.
      cmd = [
        "npx", "--no-install", "mapshaper",
        raw,
        "-filter", "udenforkommuneinddeling !== true",
        "-filter-islands", "min-area=#{MIN_ISLAND_AREA}",
        "-simplify", "#{SIMPLIFY_PCT}%", "keep-shapes",
        "-clean",
        "-filter-fields", "kode,navn,regionsnavn",
        "-o", "format=geojson", "precision=0.00001", OUTPUT.to_s
      ]
      puts "Simplifying..."
      raise "mapshaper failed" unless system(*cmd)
    end

    fc = JSON.parse(File.read(OUTPUT))
    count = fc["features"].size
    raise "expected 98 kommuner, got #{count}" unless count == 98

    puts "Wrote #{OUTPUT.relative_path_from(Rails.root)} " \
         "(#{(File.size(OUTPUT) / 1e6).round(2)} MB, #{count} kommuner)"
  end

  desc "Precompute which kommuner share a land border"
  task adjacency: :environment do
    output = Rails.root.join("lib/geo/kommune_adjacency.json")

    # mapshaper simplifies topologically, so a shared border keeps *identical*
    # vertices on both sides. That makes adjacency a matter of finding vertices
    # claimed by more than one kommune — no geometric intersection tests needed.
    vertex_owners = Hash.new { |h, k| h[k] = Set.new }

    Geo::KommuneIndex.instance.kommuner.each do |kommune|
      kommune.polygons.each do |polygon|
        polygon.each do |ring|
          ring.each { |(x, y)| vertex_owners[[ x, y ]] << kommune.kode }
        end
      end
    end

    adjacency = Hash.new { |h, k| h[k] = Set.new }
    vertex_owners.each_value do |owners|
      next if owners.size < 2

      owners.each do |kode|
        adjacency[kode].merge(owners - [ kode ])
      end
    end

    result = Geo::KommuneIndex.instance.codes.index_with { |kode| adjacency[kode].to_a.sort }
    output.write(JSON.pretty_generate(result))

    isolated = result.select { |_, neighbours| neighbours.empty? }.keys
    counts = result.values.map(&:size)

    puts "Wrote #{output.relative_path_from(Rails.root)}"
    puts "  #{result.size} kommuner, #{counts.sum / 2} border pairs"
    puts "  neighbours per kommune: min=#{counts.min} max=#{counts.max} avg=#{(counts.sum.to_f / counts.size).round(1)}"
    puts "  no land neighbours (islands): #{isolated.map { |k| "#{k} #{Geo::KommuneIndex.instance.find(k).navn}" }.join(', ')}"
  end

  desc "Verify Geo::KommuneIndex lookups against DAWA's reverse-geocode API"
  task verify: :environment do
    require "net/http"

    # Sample points spread across the country, resolved by DAWA server-side and
    # compared against our local index. This is an independent oracle: it tests
    # the simplified geometry, not just our own arithmetic.
    samples = [
      [ 12.5683, 55.6761, "Radhuspladsen, Kobenhavn" ],
      [ 10.2039, 56.1629, "Aarhus C" ],
      [ 10.6140, 55.8581, "Samso" ],
      [ 14.7000, 55.1000, "Bornholm" ],
      [  9.9187, 57.0488, "Aalborg" ],
      [ 10.3883, 55.3959, "Odense" ],
      [  8.4520, 55.4680, "Esbjerg" ],
      [ 12.0000, 54.9800, "Gedser area" ]
    ]

    mismatches = 0
    samples.each do |lon, lat, label|
      ours = Geo::KommuneIndex.instance.lookup(lat: lat, lon: lon)
      uri = URI("https://api.dataforsyningen.dk/kommuner/reverse?x=#{lon}&y=#{lat}")
      theirs = begin
        JSON.parse(Net::HTTP.get(uri))["kode"]
      rescue StandardError
        nil
      end

      ok = ours&.kode == theirs
      mismatches += 1 unless ok
      printf("%-24s ours=%-6s dawa=%-6s %s\n",
             label, ours&.kode || "nil", theirs || "nil", ok ? "ok" : "MISMATCH")
    end

    puts mismatches.zero? ? "\nAll #{samples.size} sample points agree with DAWA." : "\n#{mismatches} mismatch(es)."
  end
end
