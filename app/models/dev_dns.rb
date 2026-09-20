require "resolv"
require "fileutils"

# Development escape hatch: overrides what the resolver observes for a domain,
# so every DnsAllowlist outcome -- and every transition between them -- can be
# walked without owning a domain or waiting for a zone to propagate.
#
# WATERHOLE_FAKE_DNS (see DnsAllowlist::FakeResolver) only ever answers "this
# domain is correctly verified". The cases worth testing are the other ones: a
# record accepting a version of the documents nobody published, two records left
# up half way through an edit, a resolver that is simply down. Those are what
# this produces.
#
# Overrides live in a file because development is three processes -- the web
# server, the Solid Queue worker, and whichever rake task you just ran -- and an
# override only one of them can see is worse than no override at all. A file is
# also the thing you can read, edit and delete when you want to know what state
# you left the machine in; `rm` is a supported way to clear it.
class DevDns
  # Stored in place of a record set. No record can produce :unreachable, because
  # it is the absence of an answer rather than the content of one.
  UNREACHABLE = "unreachable"

  # Several records for one domain, on the command line and in the output. The
  # record syntax spends ";" and "=", and rake spends ",", so "|" is what is
  # left -- and it is what Result#detail already joins observed records with.
  SEPARATOR = "|"

  SCENARIOS = {
    "verified"       => "a correct record for this deployment",
    "signals"        => "verified, and opted in to cross-instance signals",
    "terms_outdated" => "for us, but accepting documents nobody published",
    "no_terms"       => "for us, with no accepted= at all",
    "missing"        => "no TXT records whatsoever",
    "other_host"     => "a record, but naming a different Waterhole",
    "ambiguous"      => "two different records for us, as during a half-finished edit",
    "unreachable"    => "the resolver fails, which must never count as removal"
  }.freeze

  class << self
    # Test seam, the same shape as LegalDocuments.directory and
    # Ip::Databases.directory.
    attr_writer :path

    def path = @path || Rails.root.join("tmp/dev_dns.json")

    # Matches the guard DnsAllowlist::FakeResolver is already chosen under:
    # never production, and never anything a real deployment can reach.
    def enabled? = !Rails.env.production?

    def all
      return {} unless enabled? && File.exist?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError => e
      # Hand-edited into nonsense. Saying so beats resolving normally and
      # leaving someone to wonder why their override stopped applying.
      Rails.logger.warn("DevDns: ignoring #{path}: #{e.message}")
      {}
    end

    # nil -- not an empty array -- when nothing is overridden: "no records" is
    # itself one of the outcomes worth testing, so the two cannot share a value.
    def records_for(domain) = all[normalise(domain)]

    def set(domain, records)
      write(all.merge(normalise(domain) => records))
      records
    end

    def clear(domain)
      overrides = all
      existed   = overrides.key?(normalise(domain))
      overrides.delete(normalise(domain))
      write(overrides)
      existed
    end

    def clear_all
      count = all.size
      write({})
      count
    end

    # A scenario name, or the records themselves: "v=waterhole1; host=..." for
    # one, joined by "|" for several. Anything with an "=" in it is taken
    # literally, which is how a typo -- the thing an admin actually does -- gets
    # tested. Returns nil for a name that is neither.
    def records_for_spec(spec)
      spec = spec.to_s.strip
      return scenario(spec) if SCENARIOS.key?(spec)
      return nil unless spec.include?("=")

      spec.split(SEPARATOR).map(&:strip).reject(&:empty?)
    end

    def scenario(name)
      case name
      when "verified"       then [ DnsAllowlist.expected_value ]
      when "signals"        then [ DnsAllowlist.expected_value(signals: true) ]
      when "terms_outdated" then [ DnsAllowlist.expected_value(terms: stale_terms_digest) ]
      when "no_terms"       then [ DnsAllowlist.expected_value(terms: nil) ]
      when "missing"        then []
      when "other_host"     then [ DnsAllowlist.expected_value(host: "elsewhere.example") ]
      when "ambiguous"      then [ DnsAllowlist.expected_value, DnsAllowlist.expected_value(signals: true) ]
      when "unreachable"    then UNREACHABLE
      end
    end

    # A version of the documents that was never published, in the shape the
    # parser expects: one segment per document. A value of the wrong shape tells
    # LegalDocuments.changed_since nothing about individual documents, so it
    # would report all of them and the per-document diff would go untested.
    def stale_terms_digest
      LegalDocuments.digest.to_s.split(":")
        .map { it == LegalDocuments::UNPUBLISHED ? it : "0" * it.length }
        .join(":")
    end

    # One record set, for the console. nil, the marker and an empty set each read
    # as themselves rather than as "", which is the distinction being tested.
    def describe(records)
      case records
      when nil         then "none (resolves normally)"
      when UNREACHABLE then "resolver failure"
      when []          then "no TXT records"
      else records.join(" #{SEPARATOR} ")
      end
    end

    # Wraps whatever resolver development would otherwise use, so a domain with
    # no override still resolves the ordinary way.
    def wrap(resolver) = enabled? ? Resolver.new(resolver) : resolver

    private

    def normalise(domain) = domain.to_s.strip.downcase

    # Deliberately no expiry. An override that disappeared on its own would look
    # exactly like the bug you were trying to reproduce.
    def write(overrides)
      return FileUtils.rm_f(path) if overrides.empty?

      FileUtils.mkdir_p(File.dirname(path))
      # Written whole and moved into place: the web server may read this file
      # between any two of these lines.
      staged = "#{path}.#{Process.pid}"
      File.write(staged, "#{JSON.pretty_generate(overrides)}\n")
      File.rename(staged, path)
      overrides
    end
  end

  class Resolver
    def initialize(inner) = @inner = inner

    def txt_records(name)
      domain   = name.to_s.chomp(".").delete_prefix("#{DnsAllowlist::PREFIX}.")
      override = DevDns.records_for(domain)

      return @inner.txt_records(name) if override.nil?
      # DnsAllowlist rescues this into :unreachable, exactly as it would a
      # resolver that is genuinely down.
      raise Resolv::ResolvError, "DevDns override for #{domain}" if override == UNREACHABLE

      override
    end
  end
end
