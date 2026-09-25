require "test_helper"

class IdentityChallengeTest < ActionDispatch::IntegrationTest
  setup do
    @instance = instances(:unverified)
    @instance.update!(actor_public_key: actor_key.public_to_pem)
  end

  def fetch(url, key: actor_key, mastodon: "4.6+")
    get URI(url).path, headers: mastodon_signed_headers(url, key:, mastodon:)
  end

  test "a fetch signed with the pinned key proves the instance, whatever the Mastodon release" do
    MastodonStubs::MASTODON_SIGNED_HEADERS.each_key do |mastodon|
      @instance.update!(actor_key_proven_at: nil)

      fetch Instances::IdentityChallenge.url_for(@instance), mastodon: mastodon

      assert_response :no_content, mastodon
      assert_in_delta Time.current, @instance.reload.actor_key_proven_at, 5.seconds
    end
  end

  # 403, never 401: a 401 makes Mastodon knock again with RFC 9421.
  test "a fetch signed with another key proves nothing" do
    fetch Instances::IdentityChallenge.url_for(@instance), key: actor_key(:replacement)

    assert_response :forbidden
    assert_nil @instance.reload.actor_key_proven_at
  end

  test "a challenge issued for a key that has since been replaced cannot be answered" do
    url = Instances::IdentityChallenge.url_for(@instance)
    @instance.update!(actor_public_key: actor_key(:replacement).public_to_pem)

    fetch url, key: actor_key(:replacement)

    assert_response :forbidden
  end

  test "an expired or forged challenge cannot be answered" do
    url = Instances::IdentityChallenge.url_for(@instance)

    travel Instances::IdentityChallenge::TTL + 1.second do
      fetch url
    end
    assert_response :forbidden

    fetch "#{Waterhole::Deployment.base_url}/identity_challenges/forged"
    assert_response :forbidden
    assert_nil @instance.reload.actor_key_proven_at
  end
end
