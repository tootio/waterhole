require "resolv"
require "ipaddr"
require "socket"

# A per-instance base_url is a domain ITS ADMIN controls, not one this
# deployment vouches for -- an admission gate that checks a DNS record only
# proves the caller owns the domain, never that the domain doesn't resolve
# into our own network. Any client that connects to a caller-supplied host
# should route its Faraday/Net::HTTP connection through here.
#
# Resolving the address ourselves AND pinning Net::HTTP to it -- rather than
# just checking and letting Net::HTTP re-resolve when it connects -- closes
# the DNS-rebinding gap: an attacker who controls the domain's DNS cannot
# swap the answer between our check and the actual connection.
#
# Skipped outside production (Rails.env.local?, i.e. development and test):
# development explicitly supports a local Mastodon on localhost (see
# SessionsController's form_action CSP), and the test suite has no network
# access and stubs requests by hostname, not by IP.
module SsrfGuard
  BlockedHost = Class.new(StandardError)

  TIMEOUT = 3 # seconds; matches DnsAllowlist::Resolver

  # List from https://github.com/mastodon/mastodon/blob/main/app/lib/private_address_check.rb
  RESERVED_RANGES = [
    # IPv4 addresses
    IPAddr.new("0.0.0.0/8"),       # Current network (only valid as source address)
    IPAddr.new("100.64.0.0/10"),   # Shared Address Space
    IPAddr.new("172.16.0.0/12"),   # Private network
    IPAddr.new("192.0.0.0/24"),    # IETF Protocol Assignments
    IPAddr.new("192.0.2.0/24"),    # TEST-NET-1, documentation and examples
    IPAddr.new("192.88.99.0/24"),  # IPv6 to IPv4 relay (includes 2002::/16)
    IPAddr.new("198.18.0.0/15"),   # Network benchmark tests
    IPAddr.new("198.51.100.0/24"), # TEST-NET-2, documentation and examples
    IPAddr.new("203.0.113.0/24"),  # TEST-NET-3, documentation and examples
    IPAddr.new("224.0.0.0/4"),     # IP multicast (former Class D network)
    IPAddr.new("240.0.0.0/4"),     # Reserved (former Class E network)
    IPAddr.new("255.255.255.255"), # Broadcast

    # IPv6 addresses
    IPAddr.new("::/96"),           # Unspecified + IPv4-compatible (deprecated, RFC 4291)
    IPAddr.new("64:ff9b::/96"),    # IPv4/IPv6 translation (RFC 6052)
    IPAddr.new("64:ff9b:1::/48"),  # IPv4/IPv6 translation (RFC 8215)
    IPAddr.new("100::/64"),        # Discard prefix (RFC 6666)
    IPAddr.new("2001::/32"),       # Teredo tunneling
    IPAddr.new("2001:10::/28"),    # Deprecated (previously ORCHID)
    IPAddr.new("2001:20::/28"),    # ORCHIDv2
    IPAddr.new("2001:db8::/32"),   # Addresses used in documentation and example source code
    IPAddr.new("2002::/16"),       # 6to4
    IPAddr.new("fc00::/7"),        # Unique local address
    IPAddr.new("3fff::/20"),       # Addresses used in documentation and example source code
    IPAddr.new("ff00::/8")         # Multicast
  ].freeze

  # RFC 6052: NAT64's well-known prefix embeds an IPv4 address in the low 32
  # bits (64:ff9b::a9fe:a9fe is 169.254.169.254), the same trick as an
  # IPv4-mapped IPv6 literal, just one layer further in.
  NAT64_PREFIX = IPAddr.new("64:ff9b::/96")

  module_function

  # Called from the Faraday net_http adapter's config block, which hands us
  # the Net::HTTP instance after it is built but before it connects.
  def pin!(http)
    return if Rails.env.local?

    address = allowed_address(http.address)
    raise BlockedHost, "#{http.address} does not resolve to a public address" unless address

    http.ipaddr = address.to_s
  end

  def allowed_address(hostname)
    addresses(hostname).find { |address| allowed?(address) }
  end

  def addresses(hostname)
    literal = begin
      IPAddr.new(hostname)
    rescue IPAddr::Error
      nil
    end
    return [ literal ] if literal

    # We prioritise IPv4 over IPv6 here. No parallel lookups and happy eyeballs race.
    Resolv::DNS.open(**Resolv::DNS::Config.default_config_hash.merge(raise_timeout_errors: true)) do |dns|
      dns.timeouts = TIMEOUT
      [ Resolv::DNS::Resource::IN::A, Resolv::DNS::Resource::IN::AAAA ].flat_map do |type|
        dns.getresources(hostname, type).map { |record| IPAddr.new(record.address.to_s) }
      end
    end
  rescue Resolv::ResolvError, IOError, SystemCallError, Timeout::Error
    []
  end

  def allowed?(address)
    address = embedded_ipv4(address) || address

    return false if address.private? || address.loopback? || address.link_local?

    RESERVED_RANGES.none? { |range| range.include?(address) }
  end

  # Unwraps an address that merely encodes another one, so the checks above
  # see the real target instead of a v6-shaped disguise for it.
  def embedded_ipv4(address)
    return address.native if address.ipv4_mapped?
    return nil unless NAT64_PREFIX.include?(address)

    IPAddr.new(address.to_i & 0xffffffff, Socket::AF_INET)
  end
end
