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

  private

  def complete_oauth(role:)
    json = { "Content-Type" => "application/json" }
    stub_request(:get, "https://newcomer.example/.well-known/oauth-authorization-server")
      .to_return(status: 404, body: "{}", headers: json)
    stub_request(:post, "https://newcomer.example/api/v1/apps")
      .to_return(status: 200, body: { "client_id" => "cid", "client_secret" => "csecret" }.to_json, headers: json)
    stub_request(:post, "https://newcomer.example/oauth/token")
      .to_return(status: 200, body: { "access_token" => "tok", "scope" => "read:accounts" }.to_json, headers: json)
    stub_request(:get, "https://newcomer.example/api/v1/accounts/verify_credentials")
      .to_return(status: 200, body: { "id" => "77", "username" => "newmod", "role" => role }.compact.to_json, headers: json)

    DnsAllowlist.stub_resolver(dns_ok) do
      post session_path, params: { domain: "newcomer.example" }
      state = Rack::Utils.parse_query(URI(response.location).query)["state"]
      get oauth_callback_path, params: { code: "abc", state: }
    end
  end
end
