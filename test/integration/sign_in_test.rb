require "test_helper"

class SignInTest < ActionDispatch::IntegrationTest
  test "a blocked domain is refused before any DNS lookup or app registration" do
    exploding = Class.new { def txt_records(_) = raise("must not be consulted") }.new

    DnsAllowlist.stub_resolver(exploding) do
      post session_path, params: { domain: "spam.example" }
    end

    assert_response :forbidden
    assert_match(/farm accounts/, response.body)
    assert_nil Instance.find_by(domain: "spam.example"),
      "a domain we refuse to serve should not even get an Instance record"
  end

  test "a domain without the DNS record is shown the record to publish" do
    DnsAllowlist.stub_resolver(dns_records([])) do
      post session_path, params: { domain: "newcomer.example" }
    end

    assert_response :forbidden
    assert_match(/_waterhole\.newcomer\.example/, response.body)
    assert_match(/host=#{Regexp.escape(Waterhole::Deployment.host)}/, response.body)
  end

  test "a domain with the record is sent on to Mastodon to authorise" do
    stub_instance_actor("newcomer.example")
    stub_request(:get, "https://newcomer.example/.well-known/oauth-authorization-server")
      .to_return(status: 404, body: "{}", headers: { "Content-Type" => "application/json" })
    stub_request(:post, "https://newcomer.example/api/v1/apps")
      .to_return(status: 200,
        body: { "client_id" => "cid", "client_secret" => "csecret" }.to_json,
        headers: { "Content-Type" => "application/json" })

    DnsAllowlist.stub_resolver(dns_ok) do
      post session_path, params: { domain: "newcomer.example" }
    end

    assert_response :redirect
    assert_match %r{\Ahttps://newcomer\.example/oauth/authorize}, response.location
    assert_match(/client_id=cid/, response.location)
  end

  test "an empty domain is rejected" do
    post session_path, params: { domain: "" }
    assert_redirected_to new_session_path
  end

  test "a callback with a tampered state is refused" do
    get oauth_callback_path, params: { code: "abc", state: "not-a-valid-signed-state" }

    assert_redirected_to new_session_path
    assert_match(/expired/, flash[:alert])
  end

  # The sign-in page makes Turbo reload it in full, so the Turbo visit that
  # follows the redirect is thrown away; the flash must survive it.
  test "a notice redirected to the sign-in page survives Turbo's reload of it" do
    sign_in_as moderators(:avery)
    delete session_path

    get new_session_path, headers: { "X-Turbo-Request-Id" => "1" }
    get new_session_path

    assert_select "[role=status]", text: /Signed out/
  end

  test "signing out ends the session" do
    sign_in_as moderators(:avery)
    assert_difference -> { Session.count }, -1 do
      delete session_path
    end
    assert_redirected_to new_session_path
  end

  # Mastodon hands admin scopes to anyone who authorises the app, so the role
  # is the only thing that separates a moderator from any other local user.
  test "a staff member with Manage Users is signed in" do
    complete_oauth(role: { "permissions" => (1 << 10).to_s })

    assert_redirected_to root_url
    assert Instance.find_by(domain: "newcomer.example").moderators.exists?(mastodon_account_id: "77")
  end

  test "an ordinary user of an admitted instance is refused" do
    assert_no_difference -> { Session.count } do
      complete_oauth(role: { "id" => "-99", "permissions" => (1 << 16).to_s })
    end

    assert_redirected_to new_session_path
    assert_match(/Manage Users/, flash[:alert])
    assert_empty Instance.find_by(domain: "newcomer.example").moderators
  end

  test "a moderator who has lost the role loses their existing sessions" do
    complete_oauth(role: { "permissions" => "1" })
    moderator = Moderator.find_by!(mastodon_account_id: "77")
    assert moderator.sessions.exists?

    complete_oauth(role: { "permissions" => "0" })

    assert_empty moderator.sessions.reload
    assert moderator.reload.token_invalidated_at
  end

  test "without a role in the payload, the admin API decides" do
    stub_request(:get, "https://newcomer.example/api/v2/admin/accounts")
      .with(query: hash_including({})).to_return(status: 403, body: { "error" => "This action is not allowed" }.to_json,
        headers: { "Content-Type" => "application/json" })

    assert_no_difference -> { Session.count } do
      complete_oauth(role: nil)
    end
    assert_redirected_to new_session_path
  end

  test "sign-in returns to the page that asked for it, in a fresh Rails session" do
    get registration_requests_path(sort: "oldest")
    before = session.id.to_s

    complete_oauth(role: { "permissions" => "1" })

    assert_redirected_to registration_requests_url(sort: "oldest")
    refute_equal before, session.id.to_s
  end

  # The choice is made before the round trip to Mastodon and must survive the
  # session reset that signing in does.
  test "remembering the instance survives the OAuth round trip, and is opt-in" do
    complete_oauth(role: { "permissions" => "1" }, remember: true)
    delete session_path
    get new_session_path
    assert_select "li button", "newcomer.example"
  end

  test "a new moderator is asked for consent before anything else" do
    complete_oauth(role: { "permissions" => "1" })
    follow_redirect!

    assert_redirected_to consent_path
    refute Instance.find_by(domain: "newcomer.example").sync_moderator, "no token is lent before consent"
  end

  # The old install lost the domain; a new one came up under it before the
  # departed instance's data was forgotten.
  test "a new install on a known domain signs in to an empty record, not the old team's" do
    instance = instances(:unverified)
    instance.update!(actor_public_key: actor_key.public_to_pem, client_id: "old-cid", client_secret: "old",
      redirect_uri: Mastodon::OAuth.redirect_uri, scopes: Mastodon::OAuth::MODERN_SCOPES)
    old_moderator = instance.moderators.create!(mastodon_account_id: "5", username: "oldmod")

    complete_oauth(role: { "permissions" => "1" }, actor: actor_key(:replacement))

    assert_redirected_to root_url
    assert_equal "cid", instance.reload.client_id, "the old OAuth app does not exist on the new server"
    assert_equal actor_key(:replacement).public_to_pem, instance.actor_public_key
    refute Moderator.exists?(old_moderator.id)
    assert_equal [ "77" ], instance.moderators.pluck(:mastodon_account_id)
  end

  # Someone took the domain on purpose and serves the old install's public key,
  # which anyone can copy. They cannot sign with it.
  test "a server publishing the old key without holding it is not signed in to" do
    instance = instances(:unverified)
    instance.update!(actor_public_key: actor_key.public_to_pem)
    old_moderator = instance.moderators.create!(mastodon_account_id: "5", username: "oldmod")

    assert_no_difference -> { Session.count } do
      complete_oauth(role: { "permissions" => "1" }, actor: actor_key, signer: actor_key(:replacement))
    end

    assert_redirected_to new_session_path
    assert_match(/could not prove/, flash[:alert]["text"])
    assert_equal sign_in_help_path(anchor: "could-not-prove"), flash[:alert]["link_url"]
    follow_redirect!
    assert_select "[role=status] a[href=?]", sign_in_help_path(anchor: "could-not-prove"), text: "What can cause this"
    assert Moderator.exists?(old_moderator.id), "nothing is wiped: the key did not change"
    refute instance.moderators.exists?(mastodon_account_id: "77")
    assert_nil instance.reload.actor_key_proven_at
  end

  test "one proof lets the whole team in for a while" do
    complete_oauth(role: { "permissions" => "1" })
    proven_at = Instance.find_by!(domain: "newcomer.example").actor_key_proven_at
    assert proven_at

    delete session_path
    complete_oauth(role: { "permissions" => "1" })

    assert_redirected_to root_url
    assert_requested :get, "https://newcomer.example/api/v2/search", query: hash_including({}), times: 1
    assert_equal proven_at, Instance.find_by!(domain: "newcomer.example").actor_key_proven_at
  end

  test "an OAuth app registered without the search scope is registered again" do
    instances(:unverified).update!(client_id: "old-cid", client_secret: "old",
      redirect_uri: Mastodon::OAuth.redirect_uri, scopes: "profile admin:read:accounts admin:write:accounts",
      oauth_metadata: { "scopes_supported" => %w[profile] })

    complete_oauth(role: { "permissions" => "1" })

    assert_equal "cid", instances(:unverified).reload.client_id
    assert_includes instances(:unverified).scopes.split, "read:search"
  end

  test "a moderator authorized before the search scope is pointed to the old authorization, once" do
    instance = instances(:unverified)
    instance.moderators.create!(mastodon_account_id: "77", username: "newmod",
      token_scopes: "profile admin:read:accounts admin:write:accounts", consented_at: Time.current)

    complete_oauth(role: { "permissions" => "1" })

    assert_match(/lists Waterhole twice/, flash[:notice]["text"])
    assert_equal "https://newcomer.example/oauth/authorized_applications", flash[:notice]["link_url"]

    delete session_path
    complete_oauth(role: { "permissions" => "1" })
    assert_equal "Signed in as @newmod@newcomer.example.", flash[:notice]
  end

  test "an instance actor without a key sends the moderator to the help page" do
    stub_instance_actor("newcomer.example", body: { "type" => "Application" })

    DnsAllowlist.stub_resolver(dns_ok) do
      post session_path, params: { domain: "newcomer.example" }
    end

    assert_redirected_to new_session_path
    assert_match(/no public key/, flash[:alert]["text"])
    assert_equal sign_in_help_path(anchor: "no-instance-actor"), flash[:alert]["link_url"]
  end

  test "a server whose instance actor cannot be read is not signed in to" do
    stub_request(:get, "https://newcomer.example/actor").to_return(status: 404)

    DnsAllowlist.stub_resolver(dns_ok) do
      post session_path, params: { domain: "newcomer.example" }
    end

    assert_redirected_to new_session_path
    assert_match(/Could not reach newcomer\.example/, flash[:alert])
  end

  private

  # `signer` is the key the server actually holds; `actor` the one it publishes.
  def complete_oauth(role:, remember: false, actor: actor_key, signer: actor)
    json = { "Content-Type" => "application/json" }
    stub_instance_actor("newcomer.example", key: actor)
    stub_mastodon_resolve("newcomer.example", key: signer)
    stub_request(:get, "https://newcomer.example/.well-known/oauth-authorization-server")
      .to_return(status: 404, body: "{}", headers: json)
    stub_request(:post, "https://newcomer.example/api/v1/apps")
      .to_return(status: 200, body: { "client_id" => "cid", "client_secret" => "csecret" }.to_json, headers: json)
    stub_request(:post, "https://newcomer.example/oauth/token")
      .to_return(status: 200, body: { "access_token" => "tok", "scope" => Mastodon::OAuth::LEGACY_SCOPES }.to_json, headers: json)
    stub_request(:get, "https://newcomer.example/api/v1/accounts/verify_credentials")
      .to_return(status: 200, body: { "id" => "77", "username" => "newmod", "role" => role }.compact.to_json, headers: json)

    DnsAllowlist.stub_resolver(dns_ok) do
      post session_path, params: { domain: "newcomer.example", remember: remember ? "1" : "0" }
      state = Rack::Utils.parse_query(URI(response.location).query)["state"]
      get oauth_callback_path, params: { code: "abc", state: }
    end
  end
end
