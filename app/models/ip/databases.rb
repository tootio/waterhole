module Ip
  # Where the MMDB files live, and what we know about how fresh they are.
  #
  # Two datasets from ip-location-db, both PDDL (public domain, no attribution):
  # they were chosen over GeoLite2 and DB-IP Lite precisely because a
  # self-hosting operator inherits no licence obligations.
  module Databases
    ASN     = "origin-asn"
    COUNTRY = "user-country"
    NAMES   = [ ASN, COUNTRY ].freeze

    BASE_URL     = "https://github.com/sapics/ip-location-db/releases/download/latest"
    CHECKSUM_URL = "https://github.com/sapics/ip-location-db/releases/download/checksum"

    # Considered stale here; surfaced to operators and, more usefully, in the
    # flag itself at the moment a moderator is deciding whether to trust it.
    STALE_AFTER = 7.days

    module_function

    def directory
      @directory || Pathname(ENV.fetch("WATERHOLE_IPDATA_DIR", Rails.root.join("storage/ipdata").to_s))
    end

    # Setter for the test suite only: whether this machine happens to have the
    # 18 MB databases downloaded must not change what the tests assert.
    def directory=(path)
      @directory = path && Pathname(path)
      Ip::Lookup.reset!
      reset_range_lists!
    end

    # Test seam, shaped like DnsAllowlist.stub_resolver.
    def stub_directory(path)
      previous, @directory = @directory, Pathname(path)
      Ip::Lookup.reset!
      reset_range_lists!
      yield
    ensure
      @directory = previous
      Ip::Lookup.reset!
      reset_range_lists!
    end

    def path_for(name) = directory.join("#{name}.mmdb")

    def metadata_path_for(name) = directory.join("#{name}.json")

    def download_url(name) = "#{BASE_URL}/#{name}.mmdb"

    def checksum_url(name) = "#{CHECKSUM_URL}/#{name}.mmdb.sha256"

    def installed?(name) = path_for(name).exist?

    def metadata(name)
      path = metadata_path_for(name)
      return {} unless path.exist?

      JSON.parse(path.read)
    rescue JSON::ParserError
      {}
    end

    def fetched_at(name)
      value = metadata(name)["fetched_at"]
      value && Time.zone.parse(value)
    end

    def stale?(name)
      at = fetched_at(name)
      at.nil? || at < STALE_AFTER.ago
    end

    def age_in_days(name)
      at = fetched_at(name)
      at && ((Time.current - at) / 1.day).floor
    end

    def ready? = NAMES.all? { installed?(it) }

    def reset_range_lists! = [ PrivateRelay, TorRelays ].each(&:reset!)

    # The range lists are listed too, but not part of ready?: without Private
    # Relay the datacenter flag still works, it just cannot tell relay users
    # apart; without the Tor list there is simply no Tor flag.
    def status
      lists = [ PrivateRelay, TorRelays ].index_by { it::NAME }
      (NAMES + lists.keys).index_with do |name|
        installed = lists[name] ? lists[name].installed? : installed?(name)
        { installed:, fetched_at: fetched_at(name), stale: stale?(name), error: metadata(name)["error"] }
      end
    end
  end
end
