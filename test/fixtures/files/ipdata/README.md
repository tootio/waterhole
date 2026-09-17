# MMDB test fixtures

Real MaxMind DB files, ~1.4 KB each, not stubs.

Stubbing the reader would leave untested the one thing that actually needs
testing: that the record schema we extract from is the schema the real files
have. These are genuine MMDB binaries read by the same `maxmind-db` gem
production uses.

They contain **documentation ranges only** (RFC 5737, RFC 3849) — no real
addresses, in a codebase whose whole subject is handling IPs carefully.

| network | ASN | organisation | country |
|---|---|---|---|
| `203.0.113.0/24` | 64500 | Example Hosting LLC | US |
| `198.51.100.0/24` | 64501 | Example Residential ISP | DE |
| `2001:db8::/32` | 64500 | Example Hosting LLC | US |

ASNs 64500/64501 are from the private-use range (RFC 6996). `192.0.2.x` is
deliberately absent so "no data" can be tested.

## Regenerating

```sh
go run .
```

Requires Go and network access for `github.com/maxmind/mmdbwriter`.
`IncludeReservedNetworks` is on because the writer otherwise refuses
documentation ranges.
