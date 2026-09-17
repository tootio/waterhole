module Ip
  # Country and ASN for a signup address.
  #
  # Enrichment is a convenience: a missing, stale or corrupt database must never
  # break a sync, so every entry point returns nil rather than raising.
  module Lookup
    REVALIDATE_AFTER = 60 # seconds between stat checks, not per lookup

    Result = Data.define(:country, :asn, :asn_org) do
      def any? = country.present? || asn.present?
    end

    Entry = Data.define(:reader, :mtime, :size, :checked_at)

    class << self
      def call(address)
        address = normalise(address)
        return nil if address.blank?

        Result.new(country: country_for(address), asn: asn_for(address).first,
          asn_org: asn_for(address).last)
      rescue StandardError => e
        Rails.logger.warn("[waterhole] IP lookup failed for #{address}: #{e.class}")
        nil
      end

      def available? = Databases.ready?

      def reset!
        mutex.synchronize { @entries = {} }
      end

      private

      def country_for(address)
        record = read(Databases::COUNTRY, address)
        return nil if record.blank?

        (record.dig("country", "iso_code") || record["country_code"] || record["country"])
          .presence&.to_s&.upcase
      end

      def asn_for(address)
        record = read(Databases::ASN, address)
        return [ nil, nil ] if record.blank?

        number = record["autonomous_system_number"] || record["asn"]
        org = record["autonomous_system_organization"] || record["as_name"] || record["name"]
        [ number&.to_i, org.presence&.to_s ]
      end

      def read(name, address)
        entry = entry_for(name)
        return nil if entry.nil?

        entry.reader.get(address)
      rescue ArgumentError, IOError
        # A malformed address, or a file replaced mid-read. Neither is worth
        # failing a sync over.
        nil
      end

      # The current reader is one fully-constructed Entry in a hash. Reads take
      # no lock: assignment is a single reference store, so no thread can observe
      # a half-built entry. The mutex guards only the reload, which happens at
      # most once a minute per file rather than once per lookup.
      def entry_for(name)
        entry = entries[name]
        return entry if entry && monotonic - entry.checked_at < REVALIDATE_AFTER

        mutex.synchronize { reload(name) }
      end

      def reload(name)
        path = Databases.path_for(name)
        return entries.delete(name) unless path.exist?

        stat = path.stat
        current = entries[name]

        if current && current.mtime == stat.mtime && current.size == stat.size
          # Unchanged; just push the next revalidation out.
          return entries[name] = current.with(checked_at: monotonic)
        end

        entries[name] = Entry.new(
          reader: MaxMind::DB.new(path.to_s, mode: MaxMind::DB::MODE_MEMORY),
          mtime: stat.mtime, size: stat.size, checked_at: monotonic
        )
      rescue StandardError => e
        Rails.logger.error("[waterhole] could not open #{name}.mmdb: #{e.class}: #{e.message}")
        entries.delete(name)
        nil
      end

      def normalise(address)
        address = address.to_s.strip
        return nil if address.blank?

        parsed = IPAddr.new(address)
        # A host arriving once as IPv4 and once as IPv4-mapped IPv6 is the same
        # host, and the databases only key the native form.
        parsed = parsed.native if parsed.ipv4_mapped?
        return nil if parsed.private? || parsed.loopback? || parsed.link_local?

        parsed.to_s
      rescue IPAddr::Error
        nil
      end

      def entries = (@entries ||= {})

      def mutex = (@mutex ||= Mutex.new)

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
