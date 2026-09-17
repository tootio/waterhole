# Hand-written stubs rather than VCR.
#
# The cases that matter here are failures -- an ambiguous 403, a truncated Link
# header, a 429 carrying a reset timestamp -- which take seconds to write by hand
# and are awkward to provoke from a real server. Recording them would also mean
# pointing VCR at a live instance with real admin credentials and then scrubbing
# emails, IPs and tokens out of the cassettes: a poor trade in a codebase whose
# whole subject is handling that data carefully.
module MastodonStubs
  def admin_account_payload(id:, username: "applicant", **overrides)
    {
      "id" => id.to_s,
      "username" => username,
      "email" => "#{username}@example.org",
      "created_at" => 2.hours.ago.iso8601,
      # A plain string, as Mastodon sends it; `ips` carries the history.
      "ip" => "198.51.100.5",
      "ips" => [ { "ip" => "198.51.100.5", "used_at" => 2.hours.ago.iso8601 } ],
      "locale" => "en",
      "invite_request" => "I would like to join this server because of the community.",
      "confirmed" => true,
      "approved" => false,
      "account" => { "username" => username, "display_name" => username.humanize,
                     "note" => "", "avatar" => "", "url" => "https://#{username}.example" }
    }.merge(overrides)
  end

  def stub_pending_accounts(instance, accounts:, next_max_id: nil)
    headers = { "Content-Type" => "application/json" }
    if next_max_id
      headers["Link"] = %(<#{instance.base_url}/api/v2/admin/accounts?max_id=#{next_max_id}>; rel="next")
    end

    stub_request(:get, "#{instance.base_url}/api/v2/admin/accounts")
      .with(query: hash_including({ "status" => "pending" }))
      .to_return(status: 200, body: accounts.to_json, headers:)
  end

  def stub_admin_account(instance, id:, status: 200, body: nil)
    stub_request(:get, "#{instance.base_url}/api/v1/admin/accounts/#{id}")
      .to_return(status:, body: (body || {}).to_json,
        headers: { "Content-Type" => "application/json" })
  end

  def stub_decision(instance, id:, action: "approve", status: 200, body: {})
    stub_request(:post, "#{instance.base_url}/api/v1/admin/accounts/#{id}/#{action}")
      .to_return(status:, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  # Mastodon's 403 body is identical whether the account is no longer pending or
  # the moderator lacks the role.
  def stub_decision_forbidden(instance, id:, action: "approve")
    stub_decision(instance, id:, action:, status: 403, body: { "error" => "This action is not allowed" })
  end

  # Resolver doubles for DnsAllowlist.
  def dns_ok(host = Waterhole::Deployment.host)
    Class.new { def initialize(h) = @h = h
      def txt_records(_) = [ "v=waterhole1; host=#{@h}" ] }.new(host)
  end

  def dns_records(records)
    Class.new { def initialize(r) = @r = r
      def txt_records(_) = @r }.new(records)
  end

  def dns_unreachable(error = Resolv::ResolvError.new("DNS resolv timeout"))
    Class.new { def initialize(e) = @e = e
      def txt_records(_) = raise(@e) }.new(error)
  end
end
