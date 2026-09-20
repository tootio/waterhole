require "resolv"

# Checks whether an instance admin has authorised THIS Waterhole deployment by
# publishing a TXT record on their domain:
#
#   _waterhole.example.social.  IN  TXT  "v=waterhole1; host=waterhole.example.org"
#
# Only someone with control of the domain's DNS can publish that, so the record
# is the instance admin's opt-in. The same goes for cross-instance signals: an
# optional `signals=on` is the admin's consent to them (see Instance#participating?).
#
# The three outcomes are deliberate, and keeping `unreachable` distinct from
# `not_allowlisted` is the whole point: a resolver failure says NOTHING about
# whether the record exists, and treating it as absence would revoke healthy
# instances and sign out their whole moderation team during a DNS blip.
class DnsAllowlist
  PREFIX  = "_waterhole"
  VERSION = "waterhole1"

  SIGNALS_ON = "on"

  # `signals` is nil when the lookup failed: that says nothing about the record.
  Result = Data.define(:outcome, :records, :error, :accepted_terms, :signals) do
    def verified?        = outcome == :verified
    def terms_outdated?  = outcome == :terms_outdated
    def not_allowlisted? = outcome == :not_allowlisted
    def ambiguous?       = outcome == :ambiguous
    def unreachable?     = outcome == :unreachable

    # A record for us that accepts no version of the documents at all -- a
    # different fix from accepting an old one.
    def accepts_no_terms? = terms_outdated? && accepted_terms.blank?

    # The documents changed since the version the record accepts.
    def changed_documents
      return [] unless terms_outdated? && !accepts_no_terms?

      LegalDocuments.changed_since(accepted_terms)
    end

    # Shown to the admin next to the expected value so a typo diagnoses itself.
    def detail
      return error if unreachable?
      return "no TXT records at #{PREFIX}" if records.empty?

      records.join(" | ")
    end
  end

  # Wraps Resolv::DNS with the settings this design depends on. Verified against
  # Ruby 4.0.6:
  #
  #   1. `raise_timeout_errors: true` is MANDATORY. Resolv::DNS::Config#resolv
  #      ends with `rescue ResolvError; raise if @raise_timeout_errors && ...`,
  #      so by default a total resolution failure returns [] -- indistinguishable
  #      from NXDOMAIN, which would silently collapse `unreachable` into
  #      `not_allowlisted`.
  #
  #   2. The config hash REPLACES the system resolver config, so it must be
  #      merged onto default_config_hash. Passing raise_timeout_errors alone
  #      leaves :nameserver unset, falls back to 0.0.0.0, and makes every lookup
  #      time out.
  #
  #   3. Query the ABSOLUTE name (trailing dot). A bare string is subject to
  #      search-list expansion, which would turn the lookup into
  #      `_waterhole.example.social.<local search domain>`.
  class Resolver
    TIMEOUT = 3 # seconds; a slow resolver must not hang a web request

    # Exposed so it can be asserted on directly: both settings below are load
    # bearing, and a refactor that quietly drops either one would break
    # revocation safety without failing anything obvious.
    def config
      Resolv::DNS::Config.default_config_hash.merge(raise_timeout_errors: true)
    end

    def txt_records(name)
      Resolv::DNS.open(**config) do |dns|
        dns.timeouts = TIMEOUT
        dns.getresources(Resolv::DNS::Name.create(name), Resolv::DNS::Resource::IN::TXT)
           .map { |record| Array(record.strings).join }
      end
    end
  end

  # Development escape hatch so the refusal page, "Check again" and revocation
  # are all walkable without owning a domain. Never consulted in production.
  class FakeResolver
    def initialize(verified_domains, host) = (@verified, @host = verified_domains, host)

    def txt_records(name)
      domain = name.chomp(".").delete_prefix("#{PREFIX}.")
      return [] unless @verified.include?(domain)

      # A correctly published record, current terms included, so the fake
      # stays verified rather than going stale on first edit -- and opted in,
      # so the seeded cross-instance flags stay visible.
      [ DnsAllowlist.expected_value(host: @host, signals: true) ]
    end
  end

  def self.call(domain, host: nil, resolver: nil, terms: :current)
    new(domain, host:, resolver:, terms:).call
  end

  def initialize(domain, host: nil, resolver: nil, terms: :current)
    @domain   = domain.to_s.downcase
    @host     = (host || Waterhole::Deployment.host).to_s.downcase
    @resolver = resolver || self.class.default_resolver
    # nil means this deployment publishes no legal documents, so no terms are
    # required and the gate behaves exactly as it did before.
    @required_terms = terms == :current ? LegalDocuments.digest : terms
  end

  # Test seam: lets a job several layers up run against a fake resolver without
  # threading the dependency through every caller.
  def self.stub_resolver(resolver)
    previous = @stubbed_resolver
    @stubbed_resolver = resolver
    yield
  ensure
    @stubbed_resolver = previous
  end

  def self.default_resolver
    return @stubbed_resolver if @stubbed_resolver

    fake = ENV["WATERHOLE_FAKE_DNS"]
    base =
      if fake.blank? || Rails.env.production?
        Resolver.new
      else
        FakeResolver.new(fake.split(",").map { it.strip.downcase }, Waterhole::Deployment.host)
      end

    # Development only, and a pass-through for every domain nobody has
    # overridden. See DevDns and waterhole:dev:dns.
    DevDns.wrap(base)
  end

  # Exactly one record per deployment, the way SPF, DMARC and MTA-STS allow
  # exactly one per name. DNS returns a record set in no fixed order -- many
  # servers rotate it -- so choosing among several records would make the
  # outcome depend on the answer's order, and flap from one check to the next.
  # More than one different record is therefore :ambiguous, never a choice.
  # Records for other deployments (other host=) are not our business.
  def call
    records = @resolver.txt_records(record_name)
    # Records differing only in spacing, case or key order say the same thing.
    addressed = records.map { parse(it) }.select { addressed_to_us?(it) }.uniq { canonical(it) }

    if addressed.empty?
      # No record naming this deployment at all.
      Result.new(outcome: :not_allowlisted, records:, error: nil, accepted_terms: nil, signals: false)
    elsif addressed.size > 1
      Result.new(outcome: :ambiguous, records:, error: nil, accepted_terms: nil, signals: nil)
    elsif @required_terms.present? && !accepts_current_terms?(addressed.first)
      # A record IS published for us, but it accepts different terms (or none).
      # Deliberately its own outcome rather than folded into :not_allowlisted --
      # the admin's remedy is different, and so is the urgency.
      Result.new(outcome: :terms_outdated, records:, error: nil,
        accepted_terms: addressed.first["accepted"], signals: signals_on?(addressed.first))
    else
      Result.new(outcome: :verified, records:, error: nil, accepted_terms: @required_terms,
        signals: signals_on?(addressed.first))
    end
  rescue Resolv::ResolvError, IOError, SystemCallError, Timeout::Error => e
    # Says nothing about whether the record exists. Never counts as removal.
    Result.new(outcome: :unreachable, records: [], error: "#{e.class}: #{e.message}",
      accepted_terms: nil, signals: nil)
  end

  def record_name = "#{PREFIX}.#{@domain}."

  # The exact record to publish, rendered for the admin.
  #
  # accepted= is appended only when this deployment actually publishes legal
  # documents; otherwise the terms gate is not active and the record stays as it
  # was, so existing instances are unaffected.
  def self.expected_record(domain, host: nil, terms: :current, signals: false)
    suggestion(domain, host:, terms:, signals:).record
  end

  # What an admin should publish, both as a zone-file line and as the bare
  # value that DNS providers' forms ask for. One computation for both.
  Suggestion = Data.define(:record, :value)

  def self.suggestion(domain, host: nil, terms: :current, signals: false)
    value = expected_value(host:, terms:, signals:)
    Suggestion.new(record: %(#{PREFIX}.#{domain}.  IN  TXT  "#{value}"), value:)
  end

  # Just the TXT content, for DNS providers whose forms ask for name and value
  # separately. Without quotes: those forms add their own.
  def self.expected_value(host: nil, terms: :current, signals: false)
    digest = terms == :current ? LegalDocuments.digest : terms
    value  = "v=#{VERSION}; host=#{host || Waterhole::Deployment.host}"
    value += "; accepted=#{digest}" if digest.present?
    value += "; signals=#{SIGNALS_ON}" if signals
    value
  end

  private

  def canonical(pairs) = pairs.transform_values(&:downcase).sort

  def parse(record)
    record.split(";").filter_map do |part|
      key, value = part.split("=", 2)
      [ key.to_s.strip.downcase, value.to_s.strip ] if value
    end.to_h
  end

  # Names this protocol version and this deployment's host.
  def addressed_to_us?(pairs)
    pairs["v"]&.casecmp?(VERSION) && pairs["host"]&.casecmp?(@host)
  end

  def accepts_current_terms?(pairs)
    pairs["accepted"]&.casecmp?(@required_terms)
  end

  def signals_on?(pairs) = pairs["signals"].to_s.casecmp?(SIGNALS_ON)
end
