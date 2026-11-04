require "test_helper"

class PushSubscriptionTest < ActiveSupport::TestCase
  include PushTestHelper

  test "accepts the push services browsers use, and names them" do
    {
      "https://fcm.googleapis.com/fcm/send/abc" => "Google",
      "https://jmt17.google.com/fcm/send/abc" => "Google",
      "https://web.push.apple.com/abc" => "Apple",
      "https://updates.push.services.mozilla.com/wpush/v2/abc" => "Mozilla",
      "https://wns2-par02p.notify.windows.com/w/?token=abc" => "Microsoft"
    }.each do |endpoint, service|
      assert_equal service, subscribe_browser(moderators(:avery), endpoint:).push_service
    end
  end

  test "refuses anything else: Waterhole posts to this from inside its network" do
    %w[
      http://fcm.googleapis.com/fcm/send/abc
      https://169.254.169.254/latest
      https://localhost/x
      https://fcm.googleapis.com.evil.example/x
      https://evilfcm.googleapis.com/x
      https://evilpush.apple.com/x
      https://fcm.googleapis.com:8443/x
      https://user@fcm.googleapis.com/x
      not\ a\ url
      javascript:alert(1)
    ].each do |endpoint|
      record = moderators(:avery).push_subscriptions.new(endpoint:, **browser_keys)
      refute record.valid?, "#{endpoint} should be refused"
    end
  end

  test "refuses keys a message could not be encrypted with" do
    good = browser_keys
    [ { p256dh: "not-a-key" }, { p256dh: "" }, { p256dh: Base64.urlsafe_encode64("\x04" + "\x01" * 64) },
      { auth: "short" }, { auth: Base64.urlsafe_encode64("x" * 17) }, { auth: "" } ].each do |bad|
      refute moderators(:avery).push_subscriptions.new(endpoint: "#{FCM}x", **good, **bad).valid?, "#{bad} should be refused"
    end
  end

  test "accepts the unpadded keys browsers send" do
    keys = browser_keys.transform_values { it.delete("=") }
    assert moderators(:avery).push_subscriptions.new(endpoint: "#{FCM}x", **keys).valid?
  end

  test "the longest endpoint allowed still fits the index, and a longer one is refused" do
    assert subscribe_browser(moderators(:avery), endpoint: FCM + "x" * (PushSubscription::MAX_ENDPOINT_LENGTH - FCM.size)).persisted?
    refute moderators(:avery).push_subscriptions.new(endpoint: FCM + "x" * PushSubscription::MAX_ENDPOINT_LENGTH, **browser_keys).valid?
  end

  test "one browser can serve two moderators, but only once each" do
    endpoint = "#{FCM}shared"
    subscribe_browser(moderators(:avery), endpoint:)

    assert subscribe_browser(moderators(:casey), endpoint:).persisted?
    refute moderators(:avery).push_subscriptions.new(endpoint:, **browser_keys).valid?
  end

  test "keys are encrypted at rest" do
    record = subscribe_browser(moderators(:avery))
    raw = PushSubscription.connection.select_one("SELECT endpoint, auth FROM push_subscriptions WHERE id = #{record.id}")

    refute_includes raw["endpoint"], "fcm.googleapis.com"
    refute_equal record.auth, raw["auth"]
  end

  test "forgetting a moderator stops everything, even one kept anonymised" do
    moderator = moderators(:avery)
    subscribe_browser(moderator)
    PushPreference.for(moderator).save!
    moderator.notes.create!(registration_request: registration_requests(:pending_alpha), body: "keeps the row") unless moderator.notes.exists?

    moderator.forget!

    assert Moderator.exists?(moderator.id), "expected the anonymised row to stay"
    assert_equal 0, PushSubscription.where(moderator_id: moderator.id).count
    assert_equal 0, PushPreference.where(moderator_id: moderator.id).count
  end

  test "a lost token keeps the rows, so signing in again resumes" do
    moderator = moderators(:avery)
    subscribe_browser(moderator)

    moderator.invalidate_token!

    assert_equal 1, moderator.push_subscriptions.count
  end
end
