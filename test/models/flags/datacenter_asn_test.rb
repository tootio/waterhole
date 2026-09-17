require "test_helper"

class Flags::DatacenterAsnTest < ActiveSupport::TestCase
  setup { @request = registration_requests(:pending_alpha) }

  test "a known hosting ASN is flagged as a warning" do
    @request.update!(ip_asn: 16509, ip_asn_org: "Amazon.com, Inc.", ip_enriched_at: Time.current)
    @request.recompute_flags!

    flag = @request.reload.flags.find_by(rule: "datacenter_asn")
    assert flag
    assert_equal "warning", flag.severity
    assert_equal "asn", flag.details["matched"]
    assert_equal 16509, flag.details["asn"]
  end

  # A name match is a heuristic -- "Hosting University of Example" is not a
  # datacenter -- so it must not look as serious as a known network.
  test "an organisation name match is only info" do
    @request.update!(ip_asn: 64500, ip_asn_org: "Example Hosting LLC", ip_enriched_at: Time.current)
    @request.recompute_flags!

    flag = @request.reload.flags.find_by(rule: "datacenter_asn")
    assert flag
    assert_equal "info", flag.severity
    assert_equal "keyword", flag.details["matched"]
    assert_equal "hosting", flag.details["pattern"]
  end

  test "a consumer ISP is not flagged" do
    @request.update!(ip_asn: 64501, ip_asn_org: "Example Residential ISP", ip_enriched_at: Time.current)
    @request.recompute_flags!

    refute @request.reload.flags.exists?(rule: "datacenter_asn")
  end

  test "an unenriched request is not flagged" do
    @request.update!(ip_asn: nil, ip_asn_org: nil)
    @request.recompute_flags!

    refute @request.reload.flags.exists?(rule: "datacenter_asn")
  end

  # The moderator is judging the evidence, not the list, so the organisation has
  # to travel with the flag.
  test "the flag names the organisation it matched" do
    @request.update!(ip_asn: 24940, ip_asn_org: "Hetzner Online GmbH", ip_enriched_at: Time.current)
    @request.recompute_flags!

    assert_equal "Hetzner Online GmbH",
      @request.reload.flags.find_by(rule: "datacenter_asn").details["org"]
  end
end
