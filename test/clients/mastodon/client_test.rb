require "test_helper"

class Mastodon::ClientTest < ActiveSupport::TestCase
  setup do
    @instance = instances(:alpha)
    @client = Mastodon::Client.new(base_url: @instance.base_url, access_token: "token-avery")
  end

  test "sends the bearer token" do
    stub_request(:get, "#{@instance.base_url}/api/v1/accounts/verify_credentials")
      .with(headers: { "Authorization" => "Bearer token-avery" })
      .to_return(status: 200, body: { "id" => "1" }.to_json,
        headers: { "Content-Type" => "application/json" })

    assert_equal "1", @client.verify_credentials["id"]
  end

  test "follows the Link header across pages" do
    stub_request(:get, "#{@instance.base_url}/api/v2/admin/accounts")
      .with(query: hash_including({ "status" => "pending" }))
      .to_return(
        { status: 200, body: [ admin_account_payload(id: 1, username: "one") ].to_json,
          headers: { "Content-Type" => "application/json",
                     "Link" => %(<#{@instance.base_url}/api/v2/admin/accounts?max_id=1>; rel="next") } },
        { status: 200, body: [ admin_account_payload(id: 2, username: "two") ].to_json,
          headers: { "Content-Type" => "application/json" } }
      )

    seen = []
    pages = @client.each_pending_account { |payload, _| seen << payload["username"] }

    assert_equal %w[one two], seen
    assert_equal 2, pages
  end

  test "stops when there is no next link" do
    stub_pending_accounts(@instance, accounts: [ admin_account_payload(id: 1) ])

    assert_equal 1, @client.each_pending_account { |_, _| }
  end

  test "a malformed Link header ends pagination rather than looping" do
    stub_request(:get, "#{@instance.base_url}/api/v2/admin/accounts")
      .with(query: hash_including({ "status" => "pending" }))
      .to_return(status: 200, body: [ admin_account_payload(id: 1) ].to_json,
        headers: { "Content-Type" => "application/json", "Link" => "this is not a link header" })

    assert_equal 1, @client.each_pending_account { |_, _| }
  end

  test "maps HTTP statuses onto distinguishable errors" do
    {
      401 => Mastodon::Unauthorized,
      403 => Mastodon::Forbidden,
      404 => Mastodon::NotFound,
      422 => Mastodon::Unprocessable,
      500 => Mastodon::ServerError
    }.each do |status, error|
      stub_request(:get, "#{@instance.base_url}/api/v1/admin/accounts/9")
        .to_return(status:, body: { "error" => "nope" }.to_json,
          headers: { "Content-Type" => "application/json" })

      assert_raises(error) { @client.admin_account(9) }
    end
  end

  test "429 carries the reset time so backoff can honour it" do
    reset = 30.seconds.from_now
    stub_request(:get, "#{@instance.base_url}/api/v1/admin/accounts/9")
      .to_return(status: 429, body: { "error" => "slow down" }.to_json,
        headers: { "Content-Type" => "application/json",
                   "X-RateLimit-Reset" => reset.iso8601, "X-RateLimit-Remaining" => "0" })

    error = assert_raises(Mastodon::RateLimited) { @client.admin_account(9) }
    assert_in_delta 30, error.retry_after, 2
  end

  test "timeouts surface as ConnectionError, not as a bare Faraday error" do
    stub_request(:get, "#{@instance.base_url}/api/v1/admin/accounts/9").to_timeout

    assert_raises(Mastodon::ConnectionError) { @client.admin_account(9) }
  end
end
