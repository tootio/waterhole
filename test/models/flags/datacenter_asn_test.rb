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

  test "chinese cloud provider ASNs are flagged as a warning" do
    [
      [ 37963, "Alibaba Cloud" ],
      [ 45090, "Tencent Cloud" ],
      [ 55990, "Huawei Cloud Service data center" ]
    ].each do |asn, org|
      @request.update!(ip_asn: asn, ip_asn_org: org, ip_enriched_at: Time.current)
      @request.recompute_flags!

      flag = @request.reload.flags.find_by(rule: "datacenter_asn")
      assert flag, "Expected ASN #{asn} (#{org}) to be flagged"
      assert_equal "warning", flag.severity
      assert_equal "asn", flag.details["matched"]
      assert_equal asn, flag.details["asn"]
    end
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

  # Private Relay leaves through Cloudflare, Akamai and Fastly: a listed ASN,
  # but an ordinary Safari user behind it.
  test "an iCloud Private Relay address is not flagged" do
    @request.update!(ip_asn: 13335, ip_asn_org: "Cloudflare, Inc.", ip_relay: "private_relay", ip_enriched_at: Time.current)
    @request.recompute_flags!

    assert_nil @request.reload.flags.find_by(rule: "datacenter_asn")
  end

  # Regression: these were listed as hosting providers but are OVH's home
  # broadband, a Chinese mobile network and an Australian ISP.
  test "consumer and mobile networks are not on the list" do
    [ 35540, 137266, 8100 ].each do |asn|
      refute_includes Flags::DatacenterAsn.asns, asn
    end
  end
end
