class AddIpEnrichmentToRegistrationRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :registration_requests, :ip_country, :string   # ISO 3166-1 alpha-2
    add_column :registration_requests, :ip_asn, :integer
    add_column :registration_requests, :ip_asn_org, :string
    # Whose relay the address belonged to when the signup was observed, if
    # anyone's: "private_relay" (iCloud Private Relay, shared by many Apple
    # users on a CDN's network) or "tor" (a running Tor relay). One column,
    # because an address is never both.
    add_column :registration_requests, :ip_relay, :string
    add_check_constraint :registration_requests, "ip_relay::text IN ('private_relay','tor')",
      name: "registration_requests_ip_relay_check"
    # nil means "never looked up", which is NOT the same as "looked up and the
    # database had nothing". Without it every re-sync would redo the lookup.
    add_column :registration_requests, :ip_enriched_at, :datetime

    # The cross-instance match key.
    #
    # IPv4 matches exactly. IPv6 matches on the /64, because hosts rotate their
    # low bits constantly under SLAAC and privacy extensions, so exact /128
    # matching would miss almost every real repeat signup.
    #
    # Generated rather than callback-maintained for two reasons:
    #   1. Anything clearing `ip` with update_columns bypasses callbacks -- a
    #      derived key would survive and keep matching people after its
    #      evidence was deleted. Postgres recomputes this to NULL instead.
    #   2. Fixtures insert with raw SQL and skip callbacks too (the email hash
    #      has to be hand-computed in registration_requests.yml because of it).
    #
    # STORED, not VIRTUAL: Postgres 18 offers both, but only STORED is indexable
    # and the index is the entire point.
    add_column :registration_requests, :ip_group, :virtual, type: :inet, stored: true, as: <<~SQL.squish
      CASE
        WHEN ip IS NULL THEN NULL
        WHEN family(ip) = 6 THEN network(set_masklen(ip, 64))
        ELSE ip
      END
    SQL

    add_index :registration_requests, :ip_group
    add_index :registration_requests, [ :instance_id, :ip_asn ]
  end
end
