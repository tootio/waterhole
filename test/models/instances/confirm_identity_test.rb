require "test_helper"

class Instances::ConfirmIdentityTest < ActiveSupport::TestCase
  setup do
    @instance = instances(:alpha)
    @instance.update!(actor_public_key: actor_key.public_to_pem, actor_key_pinned_at: 1.day.ago)
    # Fixture helpers look records up again, which fails once they are deleted.
    @avery_id = moderators(:avery).id
  end

  test "the first sign-in pins the key" do
    newcomer = instances(:unverified)
    stub_instance_actor(newcomer.domain)

    Instances::ConfirmIdentity.call(newcomer)

    assert_equal actor_key.public_to_pem, newcomer.reload.actor_public_key
    assert newcomer.actor_key_pinned_at
  end

  test "the same install keeps everything" do
    stub_instance_actor(@instance.domain)

    assert_no_changes -> { @instance.reload.actor_key_pinned_at } do
      Instances::ConfirmIdentity.call(@instance)
    end
    assert Moderator.exists?(@avery_id)
    assert_equal "alpha-client", @instance.client_id
  end

  # Mastodon could serve the same key in another encoding; only the key counts.
  test "the same key in a different PEM encoding is the same install" do
    pkcs1 = OpenSSL::ASN1::Sequence([ OpenSSL::ASN1::Integer(actor_key.n), OpenSSL::ASN1::Integer(actor_key.e) ]).to_der
    pem = "-----BEGIN RSA PUBLIC KEY-----\r\n#{[ pkcs1 ].pack("m")}-----END RSA PUBLIC KEY-----\r\n"
    stub_instance_actor(@instance.domain, body: { "publicKey" => { "publicKeyPem" => pem } })

    Instances::ConfirmIdentity.call(@instance)

    assert Moderator.exists?(@avery_id)
  end

  test "a new install on the domain starts over with nothing of the old one" do
    @instance.keyword_rules.create!(pattern: "spam", match_type: "word")
    @instance.email_templates.create!(name: "Ask", subject: "", body: "Hi")
    @instance.purged_registrations.create!(mastodon_account_id: "old-tombstone")
    stub_instance_actor(@instance.domain, key: actor_key(:replacement))

    Instances::ConfirmIdentity.call(@instance)
    @instance.reload

    assert_equal actor_key(:replacement).public_to_pem, @instance.actor_public_key
    assert_empty @instance.registration_requests
    assert_empty @instance.purged_registrations
    assert_empty @instance.keyword_rules
    assert_empty @instance.email_templates
    refute Moderator.exists?(@avery_id)
    assert RegistrationRequest.exists?(registration_requests(:other_instance).id), "other instances are untouched"

    assert @instance.unverified?, "the old admin's DNS consent and terms acceptance are not the new one's"
    assert_nil @instance.verified_at
    refute @instance.signals_approved?, "the operator approved the old team, not this one"
    refute @instance.oauth_app_current?, "the old OAuth app does not exist on the new server"
  end

  test "an unreadable key stops sign-in and changes nothing" do
    stub_instance_actor(@instance.domain, body: { "type" => "Application" })

    assert_raises(Mastodon::InvalidResponse) { Instances::ConfirmIdentity.call(@instance) }
    assert Moderator.exists?(@avery_id)
    assert_equal actor_key.public_to_pem, @instance.reload.actor_public_key
  end

  test "an unreachable actor stops sign-in and changes nothing" do
    stub_instance_actor(@instance.domain, status: 503, body: {})

    assert_raises(Mastodon::ServerError) { Instances::ConfirmIdentity.call(@instance) }
    assert Moderator.exists?(@avery_id)
  end
end
