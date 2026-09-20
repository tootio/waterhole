require "test_helper"
require "tmpdir"

class DevDnsTest < ActiveSupport::TestCase
  # Its own file per test, so the suite never writes tmp/dev_dns.json and two
  # parallel workers cannot read each other's overrides.
  setup do
    @dir = Dir.mktmpdir
    DevDns.path = File.join(@dir, "dev_dns.json")
  end

  teardown do
    DevDns.path = nil
    FileUtils.remove_entry(@dir)
  end

  test "an overridden domain answers with the override instead of the resolver" do
    DevDns.set("alpha.example", [ "v=waterhole1; host=elsewhere.example" ])

    result = DnsAllowlist.call("alpha.example", resolver: DevDns.wrap(dns_ok))

    assert result.not_allowlisted?, "the override, not the wrapped resolver, must answer"
  end

  test "a domain with no override still reaches the wrapped resolver" do
    DevDns.set("alpha.example", [])

    assert DnsAllowlist.call("beta.example", resolver: DevDns.wrap(dns_ok)).verified?
  end

  # The distinction the whole revocation design rests on: an override must be
  # able to produce "the resolver failed", which no record can express.
  test "the unreachable override raises rather than answering with no records" do
    DevDns.set("alpha.example", DevDns::UNREACHABLE)

    result = DnsAllowlist.call("alpha.example", resolver: DevDns.wrap(dns_ok))

    assert result.unreachable?
    refute result.not_allowlisted?, "a failed lookup must never read as a removed record"
  end

  test "an override of no records is an authoritative negative, not a missing override" do
    DevDns.set("alpha.example", [])

    assert DnsAllowlist.call("alpha.example", resolver: DevDns.wrap(dns_ok)).not_allowlisted?
  end

  test "every scenario produces the outcome it is named for" do
    with_legal_documents do
      expected = {
        "verified" => :verified, "signals" => :verified,
        "terms_outdated" => :terms_outdated, "no_terms" => :terms_outdated,
        "missing" => :not_allowlisted, "other_host" => :not_allowlisted,
        "ambiguous" => :ambiguous, "unreachable" => :unreachable
      }

      assert_equal DevDns::SCENARIOS.keys.sort, expected.keys.sort,
        "a scenario nobody asserts an outcome for is a scenario nobody can trust"

      expected.each do |name, outcome|
        DevDns.set("alpha.example", DevDns.scenario(name))

        assert_equal outcome, DnsAllowlist.call("alpha.example", resolver: DevDns.wrap(dns_ok)).outcome,
          "scenario #{name}"
      end
    end
  end

  test "the signals scenario opts in and the verified one does not" do
    DevDns.set("alpha.example", DevDns.scenario("signals"))
    assert DnsAllowlist.call("alpha.example", resolver: DevDns.wrap(dns_ok)).signals

    DevDns.set("alpha.example", DevDns.scenario("verified"))
    refute DnsAllowlist.call("alpha.example", resolver: DevDns.wrap(dns_ok)).signals
  end

  # A stale digest of the wrong SHAPE tells LegalDocuments nothing about
  # individual documents, so it would report every one as changed and the
  # per-document diff on the refusal page would go untested.
  test "the terms_outdated scenario names which documents changed" do
    with_legal_documents do
      DevDns.set("alpha.example", DevDns.scenario("terms_outdated"))

      result = DnsAllowlist.call("alpha.example", resolver: DevDns.wrap(dns_ok))

      refute result.accepts_no_terms?, "it accepts a version, just not the current one"
      assert_equal LegalDocuments.published.map(&:slug), result.changed_documents.map(&:slug)
    end
  end

  test "the no_terms scenario accepts no version at all" do
    with_legal_documents do
      DevDns.set("alpha.example", DevDns.scenario("no_terms"))

      assert DnsAllowlist.call("alpha.example", resolver: DevDns.wrap(dns_ok)).accepts_no_terms?
    end
  end

  test "records given literally are used as published, typos and all" do
    records = DevDns.records_for_spec("v=waterhole1; host=typo.example#{DevDns::SEPARATOR}v=waterhole0")

    assert_equal [ "v=waterhole1; host=typo.example", "v=waterhole0" ], records
  end

  test "a spec that is neither a scenario nor a record is refused" do
    assert_nil DevDns.records_for_spec("verifed")
  end

  test "clearing restores normal resolution" do
    DevDns.set("alpha.example", [])
    assert DevDns.clear("alpha.example")
    assert_nil DevDns.records_for("alpha.example")

    refute DevDns.clear("alpha.example"), "clearing what was never set reports nothing removed"
    assert DnsAllowlist.call("alpha.example", resolver: DevDns.wrap(dns_ok)).verified?
  end

  test "domains are matched however they were typed" do
    DevDns.set("  ALPHA.example ", [])

    assert_equal [], DevDns.records_for("alpha.example")
  end

  test "production never consults an override" do
    DevDns.set("alpha.example", DevDns::UNREACHABLE)
    resolver = dns_ok

    as_production do
      assert_empty DevDns.all
      assert_nil DevDns.records_for("alpha.example")
      assert_same resolver, DevDns.wrap(resolver),
        "wrapping in production would put a cache read in front of every lookup"
    end
  end

  private

  # The suite has no stubbing library, and this guard is only worth asserting
  # against the real Rails.env check rather than a seam written to please it.
  def as_production
    previous = Rails.env
    Rails.env = "production"
    yield
  ensure
    Rails.env = previous
  end
end
