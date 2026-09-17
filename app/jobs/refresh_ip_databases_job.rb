require "openssl"
require "faraday/follow_redirects"

# Refreshes the country and ASN databases daily.
#
# The upstream rebuilds them every day and publishes a SHA-256 for every asset,
# so there is no excuse for parsing an 18 MB binary on trust. A failed refresh
# always keeps the file already in place: stale data beats no data, and the
# staleness is surfaced rather than hidden.
class RefreshIpDatabasesJob < ApplicationJob
  queue_as :default

  # Accepting a checksum-correct file whose schema changed would return nil for
  # every lookup, forever and silently. These are the types we know how to read.
  KNOWN_TYPES = /asn|country/i

  retry_on Mastodon::ConnectionError, wait: :polynomially_longer, attempts: 3

  # Address lists compiled into ranges rather than MMDBs. Tor relays refresh
  # hourly instead (RefreshTorRelaysJob), but any of these can be named here.
  RANGE_LISTS = [ Ip::PrivateRelay, Ip::TorRelays ].index_by { it::NAME }.freeze

  def perform(names: Ip::Databases::NAMES + [ Ip::PrivateRelay::NAME ])
    Array(names).each do |name|
      (source = RANGE_LISTS[name]) ? refresh_range_list(source) : refresh(name)
    end
  end

  private

  def refresh(name)
    directory = Ip::Databases.directory
    FileUtils.mkdir_p(directory)

    expected = fetch_checksum(name)
    temporary = directory.join("#{name}.mmdb.download-#{Process.pid}")

    actual = download(Ip::Databases.download_url(name), temporary)

    unless actual == expected
      raise "checksum mismatch: expected #{expected}, got #{actual}"
    end

    database_type = inspect_database(temporary)

    # Atomic within a filesystem, so no reader ever sees a partial file. A reader
    # already holding the old file keeps reading it, which is exactly right.
    File.rename(temporary, Ip::Databases.path_for(name))
    write_metadata(name, sha256: actual, database_type:, path: Ip::Databases.path_for(name))

    Rails.logger.info("[waterhole] refreshed #{name}.mmdb (#{database_type})")
  rescue StandardError => e
    FileUtils.rm_f(temporary.to_s) if temporary
    record_failure(name, e)
    raise if e.is_a?(Mastodon::ConnectionError)
  end

  # Neither Apple nor Onionoo publishes a checksum, so HTTPS from their own
  # hosts is the authenticity check, and the sanity check is the size of what
  # compiles: a truncated or wrong download must not replace a good list.
  def refresh_range_list(source)
    name = source::NAME
    directory = Ip::Databases.directory
    FileUtils.mkdir_p(directory)
    download = directory.join("#{name}.download-#{Process.pid}")
    compiled = directory.join("#{name}.ranges.download-#{Process.pid}")

    sha256 = download(source::SOURCE_URL, download)
    ranges = Ip::RangeList.compile(source.parse(download))
    count = Ip::RangeList.range_count(ranges)
    if count < source::MINIMUM_RANGES
      raise "only #{count} ranges compiled from #{source::SOURCE_URL}; keeping the previous list"
    end

    Ip::RangeList.write(ranges, to: compiled)
    File.rename(compiled, source.path)
    write_metadata(name, sha256:, database_type: "#{count} merged ranges", path: source.path)

    Rails.logger.info("[waterhole] refreshed #{name} (#{count} merged ranges)")
  rescue StandardError => e
    record_failure(name, e)
    raise if e.is_a?(Mastodon::ConnectionError)
  ensure
    FileUtils.rm_f([ download.to_s, compiled.to_s ]) if download
  end

  def fetch_checksum(name)
    body = http.get(Ip::Databases.checksum_url(name)).body.to_s
    # Published either bare or as "<hex>  <filename>".
    body[/\b[0-9a-f]{64}\b/] or raise "no checksum published for #{name}"
  end

  def download(url, destination)
    digest = OpenSSL::Digest.new("SHA256")

    File.open(destination, "wb") do |file|
      response = http.get(url) do |request|
        request.options.on_data = proc do |chunk, _size, env|
          next unless env.nil? || env.status == 200

          digest << chunk
          file.write(chunk)
        end
      end
      raise "HTTP #{response.status} downloading #{url}" unless response.success?
    end

    digest.hexdigest
  end

  # The most valuable check here: the upstream is a third party rebuilding daily,
  # and a well-formed file with a changed record schema would be indistinguishable
  # from working until someone noticed every lookup was nil.
  def inspect_database(path)
    reader = MaxMind::DB.new(path.to_s, mode: MaxMind::DB::MODE_MEMORY)
    type = reader.metadata.database_type.to_s

    raise "unrecognised database type #{type.inspect}" unless type.match?(KNOWN_TYPES)

    type
  ensure
    reader&.close
  end

  def write_metadata(name, sha256:, database_type:, path:)
    Ip::Databases.metadata_path_for(name).write({
      sha256:, database_type:, fetched_at: Time.current.iso8601,
      byte_size: path.size, error: nil
    }.to_json)
  end

  def record_failure(name, error)
    Rails.logger.error("[waterhole] #{name}.mmdb refresh failed: #{error.class}: #{error.message}")
    # The network failing is tomorrow's retry. A checksum mismatch, a changed
    # schema or a vanished asset needs a person.
    unless error.is_a?(Faraday::Error) || error.is_a?(Mastodon::ConnectionError)
      Rails.error.report(error, handled: true, context: { database: name })
    end

    existing = Ip::Databases.metadata(name)
    Ip::Databases.metadata_path_for(name).write(
      existing.merge("error" => "#{error.class}: #{error.message}",
        "failed_at" => Time.current.iso8601).to_json
    )
  end

  def http
    @http ||= Faraday.new do |f|
      # GitHub release assets 302 to objects.githubusercontent.com, and Faraday 2
      # does not follow redirects on its own -- without this every download is an
      # empty HTML body and the checksum "goes missing".
      f.response :follow_redirects, limit: 5
      f.options.open_timeout = 10
      f.options.timeout = 300 # 18 MB over a slow link
      f.adapter Faraday.default_adapter
    end
  end
end
