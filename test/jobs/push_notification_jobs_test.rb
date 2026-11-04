require "test_helper"

class PushNotificationJobsTest < ActiveJob::TestCase
  include PushTestHelper

  setup do
    @moderator = moderators(:avery)
    @instance = @moderator.instance
    @moderator.update!(consented_privacy_digest: LegalDocuments.privacy_digest)
    @subscription = subscribe_browser(@moderator)
    @preference = travel_to(1.hour.ago) { PushPreference.create!(moderator: @moderator, new_frequency: "every_5_minutes") }
  end

  def dispatched
    enqueued = []
    DispatchPushNotificationsJob.perform_now
    enqueued_jobs.select { it["job_class"] == "SendModeratorPushJob" }
      .each { enqueued << GlobalID::Locator.locate(it["arguments"].first["_aj_globalid"]) }
    enqueued
  end

  test "dispatches a moderator with a preference and a browser" do
    assert_includes dispatched, @moderator
  end

  test "skips anyone who has not opted in with a browser" do
    @subscription.destroy!
    refute_includes dispatched, @moderator
  end

  test "skips a preference with no browser, or a browser with no preference" do
    @preference.destroy!
    refute_includes dispatched, @moderator
  end

  test "skips a dead token" do
    @moderator.update!(token_invalidated_at: Time.current)
    refute_includes dispatched, @moderator
  end

  test "skips outdated consent" do
    @moderator.update!(consented_at: nil)
    refute_includes dispatched, @moderator
  end

  test "skips an instance without access" do
    @instance.update!(status: "revoked")
    refute_includes dispatched, @moderator
  end

  test "a successful send moves the watermark" do
    stub_request(:post, @subscription.endpoint).to_return(status: 201)
    waiting_soon_enough
    freeze_time

    SendModeratorPushJob.perform_now(@moderator)

    assert_requested :post, @subscription.endpoint, times: 1
    assert_equal Time.current - PushNotifications::Digest::COMMIT_MARGIN, @preference.reload.new_checked_at

    SendModeratorPushJob.perform_now(@moderator)
    assert_requested :post, @subscription.endpoint, times: 1
  end

  test "total failure keeps the watermark, so the next run tries again" do
    stub_request(:post, @subscription.endpoint).to_return(status: 503)
    waiting_soon_enough

    assert_no_changes -> { @preference.reload.new_checked_at } do
      SendModeratorPushJob.perform_now(@moderator)
    end
  end

  test "one kind delivered keeps its progress when the other fails" do
    make_a_reminder_due
    stub_request(:post, @subscription.endpoint).to_return({ status: 201 }, { status: 503 })

    SendModeratorPushJob.perform_now(@moderator.reload)

    assert_requested :post, @subscription.endpoint, times: 2
    assert_in_delta Time.current, @preference.reload.new_checked_at, 1.minute
    assert_in_delta 3.days.ago, @preference.forgotten_checked_at, 1.minute
  end

  test "stops at the first message no browser took" do
    make_a_reminder_due
    stub_request(:post, @subscription.endpoint).to_return(status: 503)

    SendModeratorPushJob.perform_now(@moderator.reload)

    assert_requested :post, @subscription.endpoint, times: 1
  end

  test "does not enqueue a job for someone whose next notification is hours away" do
    @preference.update!(new_frequency: "hourly", new_checked_at: Time.current)
    refute_includes dispatched, @moderator
  end

  test "runs behind sync" do
    assert_operator SendModeratorPushJob.priority, :>, SyncInstanceJob.priority
  end

  test "nothing to say sends nothing, and moves the watermark" do
    assert_changes -> { @preference.reload.new_checked_at } do
      SendModeratorPushJob.perform_now(@moderator)
    end
    assert_not_requested :post, @subscription.endpoint
  end

  test "the recurring task is only scheduled when push is configured" do
    tasks = -> { ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/recurring.yml")).dig("production") }
    assert tasks.call.key?("dispatch_push_notifications")

    without_vapid { refute tasks.call.key?("dispatch_push_notifications") }
  end

  private

  # With something new as well, so that two messages are due.
  def make_a_reminder_due
    @preference.update_columns(forgotten_after_days: 1, daily_at: 0, forgotten_through: 3.days.ago, forgotten_checked_at: 3.days.ago)
    travel_to(2.days.ago) { waiting_request(@instance) }
    waiting_soon_enough
  end

  # Far enough back for Digest to count it.
  def waiting_soon_enough = travel_to(1.minute.ago) { waiting_request(@instance) }
end
