require "test_helper"

# Mastodon lists unconfirmed signups as pending, but only tells staff about a
# pending account once its email is confirmed, and deletes it if that never
# happens within a week.
class UnconfirmedEmailTest < ActiveSupport::TestCase
  setup { @request = registration_requests(:pending_alpha) }

  test "a vanished account is read as expired only when it could have expired" do
    @request.assign_attributes(confirmed: false, confirmation_requested_at: 8.days.ago)
    assert_equal "expired", @request.deleted_upstream_status

    @request.assign_attributes(confirmed: false, confirmation_requested_at: 6.days.ago)
    assert_equal "rejected_elsewhere", @request.deleted_upstream_status, "too young to have expired"

    @request.assign_attributes(confirmed: true, confirmation_requested_at: 30.days.ago)
    assert_equal "rejected_elsewhere", @request.deleted_upstream_status, "confirmed accounts never expire"
  end

  def signup(**attributes)
    @request.instance.registration_requests.create!(mastodon_account_id: SecureRandom.hex(8), username: "signup",
      confirmed: false, **attributes)
  end

  test "an account frozen from the start was never sent the mail, so it does not expire" do
    request = signup(disabled: true, signed_up_at: 8.days.ago)

    assert request.awaiting_review?
    assert_nil request.confirmation_requested_at
    assert_equal "rejected_elsewhere", request.deleted_upstream_status
  end

  test "an account frozen after its mail went out still expires" do
    request = signup(signed_up_at: 8.days.ago)
    assert_equal request.signed_up_at, request.confirmation_requested_at

    request.update!(disabled: true)

    assert_equal "expired", request.deleted_upstream_status
  end

  test "an old account unfrozen just now has only just been sent its mail" do
    request = signup(disabled: true, signed_up_at: 30.days.ago)

    request.update!(disabled: false)

    assert_equal "rejected_elsewhere", request.deleted_upstream_status, "inside the week it has been given"
    travel_to(8.days.from_now) { assert_equal "expired", request.deleted_upstream_status }
  end

  test "frozen only counts while the request is pending" do
    @request.assign_attributes(confirmed: true, disabled: true)
    assert @request.account_frozen?
    assert @request.awaiting_review?

    @request.status = "approved"
    refute @request.account_frozen?
  end

  test "an expired signup is not a rejection to re-apply after" do
    @request.update!(status: "expired", resolved_at: Time.current)
    again = @request.instance.registration_requests.create!(mastodon_account_id: "9301",
      username: "again", email: @request.email, signed_up_at: 1.minute.ago,
      invite_request: "Fixed the typo in my address this time.")

    assert_nil Flags::Reapplication.call(again)

    @request.update!(status: "rejected")
    assert Flags::Reapplication.call(again), "a real rejection still counts"
  end

  test "expiry is resolved, and no longer counts as active on other instances" do
    @request.update!(status: "expired", resolved_at: Time.current)

    assert @request.resolved?
    refute @request.active?
  end
end
