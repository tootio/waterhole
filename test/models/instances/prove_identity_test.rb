require "test_helper"

class Instances::ProveIdentityTest < ActiveSupport::TestCase
  setup do
    @instance = instances(:alpha)
    @instance.update!(actor_public_key: actor_key.public_to_pem)
    @client = Mastodon::Client.new(base_url: @instance.base_url, access_token: "tok")
  end

  test "a recent proof is not asked for again" do
    @instance.update!(actor_key_proven_at: 30.minutes.ago)

    Instances::ProveIdentity.call(@instance, @client)

    assert_not_requested :get, "#{@instance.base_url}/api/v2/search", query: hash_including({})
  end

  test "a stale proof is asked for again, and a server that never answers fails" do
    @instance.update!(actor_key_proven_at: 2.hours.ago)
    stub_request(:get, "#{@instance.base_url}/api/v2/search").with(query: hash_including("resolve" => "true"))
      .to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })

    assert_raises(Instances::ProveIdentity::Unproven) { Instances::ProveIdentity.call(@instance, @client) }
  end

  test "a token without the search scope fails the sign-in" do
    stub_request(:get, "#{@instance.base_url}/api/v2/search").with(query: hash_including({}))
      .to_return(status: 403, body: { "error" => "This action is outside the authorized scopes" }.to_json,
        headers: { "Content-Type" => "application/json" })

    assert_raises(Mastodon::Forbidden) { Instances::ProveIdentity.call(@instance, @client) }
  end
end
