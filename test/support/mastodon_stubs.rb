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

  # Payloads for the instance's pending rows, i.e. an upstream queue that still
  # holds everything we know of. A sync whose listing leaves them out would go
  # and verify each one as a departure.
  def pending_account_payloads(instance, except: nil)
    instance.registration_requests.pending.reject { except && it.id == except.id }.map do |request|
      admin_account_payload(id: request.mastodon_account_id, username: request.username)
    end
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

  def stub_decision_rate_limited(instance, id:, action: "approve", reset_at: 30.seconds.from_now)
    stub_request(:post, "#{instance.base_url}/api/v1/admin/accounts/#{id}/#{action}")
      .to_return(status: 429, body: { "error" => "Too many requests" }.to_json,
        headers: { "Content-Type" => "application/json",
                   "X-RateLimit-Remaining" => "0", "X-RateLimit-Reset" => reset_at.iso8601 })
  end

  # Two installs' worth of instance actor keys, generated once per process:
  # RSA generation is slow enough to notice across the suite.
  ACTOR_KEYS = Hash.new { |h, name| h[name] = OpenSSL::PKey::RSA.generate(2048) }

  def actor_key(name = :original) = ACTOR_KEYS[name]

  def stub_instance_actor(domain, key: actor_key, status: 200, body: nil)
    body ||= { "id" => "https://#{domain}/actor", "type" => "Application",
               "publicKey" => { "id" => "https://#{domain}/actor#main-key",
                                "owner" => "https://#{domain}/actor",
                                "publicKeyPem" => key.public_to_pem } }
    stub_request(:get, "https://#{domain}/actor")
      .with(headers: { "Accept" => "application/activity+json" })
      .to_return(status:, body: body.to_json, headers: { "Content-Type" => "application/activity+json; charset=utf-8" })
  end

  # What Mastodon's FetchResourceService sends as Accept, and the headers each
  # release line signs, in order. Up to 4.5 Accept is signed too; 4.4 moved the
  # request target to the end; 4.6 stopped signing Accept.
  MASTODON_FETCH_ACCEPT = 'application/activity+json, application/ld+json; profile="https://www.w3.org/ns/activitystreams", text/html;q=0.1'.freeze
  MASTODON_SIGNED_HEADERS = {
    "3.5-4.3" => %w[(request-target) host date accept],
    "4.4-4.5" => %w[host date accept (request-target)],
    "4.6+"    => %w[host date (request-target)]
  }.freeze

  # Headers for a GET signed as the given Mastodon release line signs its fetches.
  def mastodon_signed_headers(url, key: actor_key, key_id: "https://newcomer.example/actor#main-key",
    date: Time.current, mastodon: "4.6+")
    uri = URI(url)
    target = uri.query ? "#{uri.path}?#{uri.query}" : uri.path
    sent = { "Host" => uri.host + (uri.port == uri.default_port ? "" : ":#{uri.port}"), "Date" => date.httpdate,
             "Accept" => MASTODON_FETCH_ACCEPT }
    values = sent.transform_keys(&:downcase).merge("(request-target)" => "get #{target}")
    names = MASTODON_SIGNED_HEADERS.fetch(mastodon)
    string = names.map { |name| "#{name}: #{values.fetch(name)}" }.join("\n")
    signature = Base64.strict_encode64(key.sign(OpenSSL::Digest.new("SHA256"), string))

    sent.merge("Signature" =>
      %(keyId="#{key_id}",algorithm="rsa-sha256",headers="#{names.join(" ")}",signature="#{signature}"))
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
