# Seeds a working queue with no Mastodon server and no domain of your own.
#
# Two instances, both already verified and both opted into cross-instance
# signals, so every flag -- including email_active_elsewhere, which needs a
# second participating instance -- is actually visible.
return if Rails.env.production?

puts "Seeding Waterhole…"

Flag.delete_all
Note.delete_all
Decision.delete_all
RegistrationRequest.delete_all
Session.delete_all
SyncRun.delete_all              # references instances; re-seeding fails without it
Instance.update_all(sync_moderator_id: nil)
Moderator.delete_all
KeywordRule.delete_all
PurgedRegistration.delete_all
Instance.delete_all
DomainPolicy.delete_all

# Seeded as already accepting whatever documents this deployment currently
# publishes, so a seeded instance is coherent rather than going stale at the very
# first verification pass.
terms = LegalDocuments.digest

alpha = Instance.create!(domain: "alpha.example", title: "Alpha", status: "verified",
  verified_at: Time.current, signals_opted_in: true, signals_approved: true, accepted_terms_digest: terms,
  scopes: Mastodon::OAuth::MODERN_SCOPES, last_synced_at: 3.minutes.ago)
beta = Instance.create!(domain: "beta.example", title: "Beta", status: "verified",
  verified_at: Time.current, signals_opted_in: true, signals_approved: true, accepted_terms_digest: terms,
  scopes: Mastodon::OAuth::MODERN_SCOPES, last_synced_at: 9.minutes.ago)

# A domain this Waterhole refuses to serve, so the blocklist is demonstrable.
DomainPolicy.create!(domain: "spam-instance.example", kind: "blocked",
  reason: "Repeatedly used to farm accounts.")

avery = alpha.moderators.create!(mastodon_account_id: "1", username: "avery",
  display_name: "Avery", access_token: "seed-token-avery", last_authenticated_at: Time.current, consented_at: Time.current)
blake = alpha.moderators.create!(mastodon_account_id: "2", username: "blake",
  display_name: "Blake", access_token: "seed-token-blake", last_authenticated_at: 1.day.ago, consented_at: Time.current)
beta.moderators.create!(mastodon_account_id: "3", username: "casey",
  display_name: "Casey", access_token: "seed-token-casey", last_authenticated_at: Time.current, consented_at: Time.current)
alpha.update!(sync_moderator: avery)
beta.update!(sync_moderator: beta.moderators.first)

KeywordRule.create!(instance: alpha, pattern: "airdrop", match_type: "word",
  severity: "critical", description: "Crypto spam")
KeywordRule.create!(instance: alpha, pattern: "seo", match_type: "word",
  severity: "warning", description: "Marketing accounts")

def request!(instance, id, **attrs)
  instance.registration_requests.create!(
    mastodon_account_id: id,
    signed_up_at: rand(1..72).hours.ago,
    last_seen_in_queue_at: Time.current,
    **attrs
  )
end

requests = []
requests << request!(alpha, "101", username: "rowan", email: "rowan@fastmail.com",
  invite_request: "I've been on a smaller server for two years and I'm looking for somewhere with a stronger local community around ecology and field recording. I moderate a Discord for the same interest.",
  ip: "198.51.100.12", confirmed: true, display_name: "Rowan")

requests << request!(alpha, "102", username: "nocontext", email: "x9f2@mailinator.com",
  invite_request: nil, ip: "203.0.113.77", confirmed: false)

requests << request!(alpha, "103", username: "brief", email: "brief@example.org",
  invite_request: "hi", ip: "198.51.100.44", confirmed: true)

requests << request!(alpha, "104", username: "houseshare_a", email: "a@example.org",
  invite_request: "My flatmate is applying too, we heard about this server from a friend.",
  ip: "192.0.2.50", confirmed: true)
requests << request!(alpha, "105", username: "houseshare_b", email: "b@example.org",
  invite_request: "Applying alongside my flatmate, same connection.",
  ip: "192.0.2.50", confirmed: true)

requests << request!(alpha, "106", username: "shill", email: "promo@example.net",
  invite_request: "join my airdrop, guaranteed returns for early members",
  ip: "203.0.113.200", confirmed: false)

# Signed up from a hosting network: country and ASN are normally filled in by
# sync, but seeded directly here so the panel and the datacenter flag are
# demonstrable without downloading 18 MB of databases.
requests << request!(alpha, "111", username: "from_a_datacenter", email: "dc@example.org",
  invite_request: "I would like to join and take part in the local discussions here.",
  ip: "203.0.113.42", ip_country: "US", ip_asn: 16509,
  ip_asn_org: "Amazon.com, Inc.", ip_enriched_at: Time.current, confirmed: true)

# The same IPv6 /64 on both participating instances: hosts rotate their low bits,
# so these two would not match on an exact comparison.
requests << request!(alpha, "112", username: "v6_here", email: "v6a@example.org",
  invite_request: "Applying from home, where we have a normal fibre connection.",
  ip: "2001:db8:1234:5678:aaaa:bbbb:cccc:dddd",
  ip_country: "DE", ip_asn: 3320, ip_asn_org: "Deutsche Telekom AG",
  ip_enriched_at: Time.current, confirmed: true)
requests << request!(beta, "113", username: "v6_there", email: "v6b@example.org",
  invite_request: "Applying from home, where we have a normal fibre connection.",
  ip: "2001:db8:1234:5678:1111:2222:3333:4444",
  ip_country: "DE", ip_asn: 3320, ip_asn_org: "Deutsche Telekom AG",
  ip_enriched_at: Time.current, confirmed: true)

# Same human, on both participating instances, using plus-addressing and dots.
requests << request!(alpha, "107", username: "jules_a", email: "Ju.les+alpha@gmail.com",
  invite_request: "Interested in the local art scene here and want to post my sketches.",
  ip: "198.51.100.90", confirmed: true)
requests << request!(beta, "108", username: "jules_b", email: "jules@gmail.com",
  invite_request: "Interested in the local art scene here and want to post my sketches.",
  ip: "198.51.100.91", confirmed: true)

# A signup farm's template, filled in with different names, from different
# networks on both participating instances: only the join reason gives it away.
template = "Hi, I am %s, a digital artist from Berlin and I would love to share my illustrations and meet other creative people here."
requests << request!(alpha, "114", username: "anna_art", email: "anna.art@example.net",
  invite_request: format(template, "Anna"), ip: "192.0.2.44", confirmed: true)
requests << request!(beta, "115", username: "marco_art", email: "marco.art@example.com",
  invite_request: format(template, "Marco"), ip: "198.51.100.120", confirmed: true)

# Previously rejected, now back with a new account: only our mirror remembers.
request!(alpha, "109", username: "returning_old", email: "again@example.net",
  invite_request: "let me in", status: "rejected", resolved_at: 6.days.ago, ip: "203.0.113.5")
requests << request!(alpha, "110", username: "returning_new", email: "again@example.net",
  invite_request: "Second time asking, I hope that's alright. I read the rules properly now.",
  ip: "203.0.113.5", confirmed: true)

claimed = requests.first
claimed.update!(claimed_by: blake, claimed_at: 20.minutes.ago)
note = claimed.notes.create!(moderator: blake, body: "Looks genuine to me — the Discord checks out. Anyone object?")
claimed.notes.create!(moderator: avery, parent: note, body: "No objection. Approve when you're ready.")

requests.each(&:recompute_flags!)

puts "  #{Instance.count} instances, #{Moderator.count} moderators, #{RegistrationRequest.count} requests, #{Flag.count} flags"
puts "  Sign in at /session/new as any instance; for a real sign-in you need a Mastodon server."
puts "  Legal documents: #{LegalDocuments.published? ? "published" : "EXAMPLES ONLY - run waterhole:legal:install"}"
puts "  IP databases:    #{Ip::Databases.ready? ? "installed" : "not installed - run waterhole:ipdata:refresh"}"
puts "  To browse the seeded queue, run: bin/rails waterhole:impersonate[avery]"
