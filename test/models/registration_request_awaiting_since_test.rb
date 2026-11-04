require "test_helper"

class RegistrationRequestAwaitingSinceTest < ActiveSupport::TestCase
  include PushTestHelper

  setup { @instance = instances(:alpha) }

  test "starts when a confirmed request arrives" do
    freeze_time
    assert_equal Time.current, waiting_request(@instance).awaiting_since
  end

  test "starts at the late confirmation, not at sign-up" do
    request = waiting_request(@instance, confirmed: false, signed_up_at: 3.days.ago)
    assert_nil request.awaiting_since

    freeze_time
    request.update!(confirmed: true)
    assert_equal Time.current, request.awaiting_since
  end

  test "pending_since follows being pending, confirmed or not" do
    request = travel_to(2.days.ago) { waiting_request(@instance, confirmed: false) }
    assert_in_delta 2.days.ago, request.pending_since, 1.minute

    request.update!(status: "rejected_elsewhere")
    assert_nil request.pending_since

    freeze_time
    request.update!(status: "pending")
    assert_equal Time.current, request.pending_since
  end

  test "an unrelated update does not restart it" do
    request = travel_to(2.days.ago) { waiting_request(@instance) }

    assert_no_changes -> { request.reload.awaiting_since } do
      request.update!(username: "renamed")
    end
  end

  test "ends on leaving the queue and starts over on coming back" do
    request = travel_to(2.days.ago) { waiting_request(@instance) }

    request.update!(status: "rejected_elsewhere")
    assert_nil request.awaiting_since

    freeze_time
    request.update!(status: "pending")
    assert_equal Time.current, request.awaiting_since
  end

  test "the migration backfills only what is awaiting review" do
    awaiting = travel_to(2.days.ago) { waiting_request(@instance) }
    unconfirmed = waiting_request(@instance, confirmed: false)
    [ awaiting, unconfirmed ].each { it.update_columns(awaiting_since: nil) }

    sql = "UPDATE registration_requests SET awaiting_since = signed_up_at WHERE status = 'pending' AND confirmed"
    assert_includes File.read(Rails.root.join("db/migrate/20261104120000_create_push_notifications.rb")).squish, sql
    RegistrationRequest.connection.execute(sql)

    assert_in_delta awaiting.signed_up_at, awaiting.reload.awaiting_since, 1.second
    assert_nil unconfirmed.reload.awaiting_since
  end
end
