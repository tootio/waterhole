require "test_helper"

class SsrfGuardTest < ActiveSupport::TestCase
  test "allows public addresses" do
    assert SsrfGuard.allowed?(IPAddr.new("8.8.8.8"))
    assert SsrfGuard.allowed?(IPAddr.new("2001:4860:4860::8888"))
  end

  test "blocks private, loopback, and link-local addresses" do
    refute SsrfGuard.allowed?(IPAddr.new("10.0.0.5"))
    refute SsrfGuard.allowed?(IPAddr.new("172.16.0.1"))
    refute SsrfGuard.allowed?(IPAddr.new("192.168.1.1"))
    refute SsrfGuard.allowed?(IPAddr.new("127.0.0.1"))
    refute SsrfGuard.allowed?(IPAddr.new("169.254.169.254")) # cloud metadata
    refute SsrfGuard.allowed?(IPAddr.new("::1"))
    refute SsrfGuard.allowed?(IPAddr.new("fd00::1"))
  end

  test "blocks the carrier-grade NAT / shared address space range (RFC 6598)" do
    refute SsrfGuard.allowed?(IPAddr.new("100.64.0.1"))
    refute SsrfGuard.allowed?(IPAddr.new("100.100.100.100"))
    refute SsrfGuard.allowed?(IPAddr.new("100.127.255.254"))
  end

  test "the shared address space range does not swallow neighbouring public addresses" do
    assert SsrfGuard.allowed?(IPAddr.new("100.63.255.255"))
    assert SsrfGuard.allowed?(IPAddr.new("100.128.0.0"))
  end

  test "unwraps IPv4-mapped IPv6 addresses before checking" do
    refute SsrfGuard.allowed?(IPAddr.new("::ffff:127.0.0.1"))
    assert SsrfGuard.allowed?(IPAddr.new("::ffff:8.8.8.8"))
  end

  test "blocks deprecated IPv4-compatible IPv6 addresses (::a.b.c.d, RFC 4291)" do
    refute SsrfGuard.allowed?(IPAddr.new("::169.254.169.254")) # cloud metadata
    refute SsrfGuard.allowed?(IPAddr.new("::10.0.0.1"))
    refute SsrfGuard.allowed?(IPAddr.new("::8.8.8.8")) # not routable as IPv4 either way
  end

  test "unwraps a NAT64-embedded IPv4 address before checking" do
    refute SsrfGuard.allowed?(IPAddr.new("64:ff9b::a9fe:a9fe")) # embeds 169.254.169.254
    assert SsrfGuard.allowed?(IPAddr.new("64:ff9b::808:808"))   # embeds 8.8.8.8
  end

  # see https://github.com/mastodon/mastodon/blob/main/spec/lib/private_address_check_spec.rb
  test "refute the same addresses as Mastodon" do
    %w[192.168.1.7 0.0.0.0 127.0.0.1 ::ffff:0.0.0.1 ::127.0.0.1 ::ffff:127.0.0.1 ::ffff:10.0.0.1 ::ffff:169.254.169.254 ::].each do |private_address|
      refute SsrfGuard.allowed?(IPAddr.new(private_address))
    end
  end

  test "a literal IP address in the host position is checked directly, without a DNS lookup" do
    assert_equal [ IPAddr.new("127.0.0.1") ], SsrfGuard.addresses("127.0.0.1")
  end

  test "pin! is a no-op in development and test, where Rails.env.local? is true" do
    assert Rails.env.local?

    http = Net::HTTP.new("127.0.0.1", 443)
    SsrfGuard.pin!(http)

    assert_nil http.ipaddr
  end

  test "pin! pins the connection to the resolved, allowed address" do
    with_production_env do
      http = Net::HTTP.new("8.8.8.8", 443)
      SsrfGuard.pin!(http)

      assert_equal "8.8.8.8", http.ipaddr
    end
  end

  test "pin! blocks a host that resolves to a private address" do
    with_production_env do
      http = Net::HTTP.new("127.0.0.1", 443)

      assert_raises(SsrfGuard::BlockedHost) { SsrfGuard.pin!(http) }
    end
  end

  private

  # Matches the pattern in test/models/dev_dns_test.rb and test/lib/deployment_test.rb:
  # Rails.env is a StringInquirer, swapped for the duration of one test.
  def with_production_env
    previous = Rails.env
    Rails.env = "production"
    yield
  ensure
    Rails.env = previous
  end
end
