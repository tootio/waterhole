require "test_helper"

class Ip::LookupTest < ActiveSupport::TestCase
  test "resolves country and ASN for IPv4" do
    with_ip_databases do
      result = Ip::Lookup.call(IpStubs::DATACENTER_V4)

      assert_equal "US", result.country
      assert_equal 64500, result.asn
      assert_equal "Example Hosting LLC", result.asn_org
    end
  end

  test "resolves IPv6" do
    with_ip_databases do
      result = Ip::Lookup.call(IpStubs::DATACENTER_V6)

      assert_equal "US", result.country
      assert_equal 64500, result.asn
    end
  end

  # The same host arriving once as IPv4 and once as IPv4-mapped IPv6 must resolve
  # identically; the databases only key the native form.
  test "normalises IPv4-mapped IPv6" do
    with_ip_databases do
      assert_equal Ip::Lookup.call(IpStubs::DATACENTER_V4),
        Ip::Lookup.call("::ffff:#{IpStubs::DATACENTER_V4}")
    end
  end

  test "an address the databases do not cover yields empty values, not an error" do
    with_ip_databases do
      result = Ip::Lookup.call(IpStubs::UNKNOWN_V4)

      assert_nil result.country
      assert_nil result.asn
      refute result.any?
    end
  end

  test "private and malformed addresses are skipped" do
    with_ip_databases do
      [ "10.0.0.1", "127.0.0.1", "169.254.1.1", "not-an-ip", "", nil ].each do |address|
        assert_nil Ip::Lookup.call(address), "expected nil for #{address.inspect}"
      end
    end
  end

  # Enrichment is a convenience; it must never take a sync down with it.
  test "with no databases installed lookups return empty rather than raising" do
    Dir.mktmpdir do |dir|
      Ip::Databases.stub_directory(dir) do
        refute Ip::Lookup.available?
        assert_nothing_raised { Ip::Lookup.call(IpStubs::DATACENTER_V4) }
        refute Ip::Lookup.call(IpStubs::DATACENTER_V4).any?
      end
    end
  end

  test "a corrupt database file degrades to no data" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "origin-asn.mmdb"), "this is not an mmdb file")
      File.write(File.join(dir, "user-country.mmdb"), "nor is this")

      Ip::Databases.stub_directory(dir) do
        assert_nothing_raised { Ip::Lookup.call(IpStubs::DATACENTER_V4) }
        assert_nil Ip::Lookup.call(IpStubs::DATACENTER_V4).asn
      end
    end
  end

  test "picks up a file swapped underneath it without a restart" do
    Dir.mktmpdir do |dir|
      Ip::Databases.stub_directory(dir) do
        assert_nil Ip::Lookup.call(IpStubs::DATACENTER_V4).asn

        IpStubs::FIXTURE_DIR.glob("*.mmdb").each { FileUtils.cp(it, dir) }
        Ip::Lookup.reset! # stands in for the 60s revalidation window elapsing

        assert_equal 64500, Ip::Lookup.call(IpStubs::DATACENTER_V4).asn
      end
    end
  end
end
