require "test_helper"

class DnsAllowlistTest < ActiveSupport::TestCase
  test "a record naming this deployment verifies" do
    assert DnsAllowlist.call("alpha.example", resolver: dns_ok).verified?
  end

  test "a record naming a different deployment does not verify" do
    result = DnsAllowlist.call("alpha.example", resolver: dns_records([ "v=waterhole1; host=someone-else.example" ]))

    assert result.not_allowlisted?
    assert_includes result.detail, "someone-else.example"
  end

  test "joins a payload split across several TXT strings" do
    # TXT payloads over 255 chars arrive as multiple strings; comparing them
    # unjoined silently fails to match a perfectly good record.
    split = Class.new do
      def txt_records(_) = [ [ "v=waterhole1; ho", "st=#{Waterhole::Deployment.host}" ].join ]
    end.new

    assert DnsAllowlist.call("alpha.example", resolver: split).verified?
  end

  test "host comparison ignores case" do
    upper = dns_records([ "V=WATERHOLE1; HOST=#{Waterhole::Deployment.host.upcase}" ])

    assert DnsAllowlist.call("alpha.example", resolver: upper).verified?
  end

  test "NXDOMAIN is an authoritative negative" do
    assert DnsAllowlist.call("alpha.example", resolver: dns_records([])).not_allowlisted?
  end

  # The property the whole revocation design rests on.
  test "a resolver timeout is unreachable, NOT a missing record" do
    result = DnsAllowlist.call("alpha.example", resolver: dns_unreachable)

    assert result.unreachable?, "a timeout must not be reported as unreachable's opposite"
    refute result.not_allowlisted?, "treating a timeout as absence would revoke healthy instances"
  end

  test "socket-level failures are unreachable too" do
    assert DnsAllowlist.call("alpha.example", resolver: dns_unreachable(Errno::ECONNREFUSED.new)).unreachable?
  end

  test "queries the absolute name so the resolver's search list cannot rewrite it" do
    spy = Class.new do
      attr_reader :asked
      def txt_records(name) = (@asked = name.to_s) && []
    end.new

    DnsAllowlist.call("alpha.example", resolver: spy)

    assert_equal "_waterhole.alpha.example.", spy.asked
  end

  # Pins both stdlib traps: Resolv::DNS swallows timeouts unless
  # raise_timeout_errors is set, and a bare config hash wipes the system
  # nameservers so every lookup times out.
  test "the real resolver opts into timeout errors and keeps the system nameservers" do
    captured = DnsAllowlist::Resolver.new.config

    assert_equal true, captured[:raise_timeout_errors],
      "without this, Resolv::DNS reports a timeout as an empty result"
    assert captured[:nameserver].present? || captured[:nameserver_port].present?,
      "a bare config hash falls back to 0.0.0.0 and times out every lookup"
  end

  test "a record with no accepted_tos is terms_outdated, not a missing record" do
    with_legal_documents do
      result = DnsAllowlist.call("alpha.example", resolver: dns_record)

      assert result.terms_outdated?
      refute result.not_allowlisted?, "the record IS published; the remedy is different"
      refute result.unreachable?
    end
  end

  test "a record accepting older terms is terms_outdated and reports what it accepted" do
    with_legal_documents do
      result = DnsAllowlist.call("alpha.example", resolver: dns_record(accepted_tos: "abc" * 16))

      assert result.terms_outdated?
      assert_equal "abc" * 16, result.accepted_terms
    end
  end

  test "a wrong host is not allowlisted even when the terms are current" do
    with_legal_documents do
      resolver = dns_record(accepted_tos: LegalDocuments.digest, host: "someone-else.example")

      assert DnsAllowlist.call("alpha.example", resolver:).not_allowlisted?,
        "host is checked first: a record addressed elsewhere is not a terms problem"
    end
  end

  test "with no documents published a host-only record still verifies" do
    assert DnsAllowlist.call("alpha.example", resolver: dns_record).verified?,
      "adding the feature must not invalidate deployments that publish no documents"
  end

  test "the expected record carries the current digest" do
    with_legal_documents do
      assert_includes DnsAllowlist.expected_record("alpha.example"),
        "accepted_tos=#{LegalDocuments.digest}"
    end
  end

  test "expected_record renders what the admin must publish" do
    record = DnsAllowlist.expected_record("alpha.example")

    assert_includes record, "_waterhole.alpha.example."
    assert_includes record, "host=#{Waterhole::Deployment.host}"
  end
end
