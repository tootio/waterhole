require "test_helper"

# The badge is broadcast as a replacement of one element, never as a page
# refresh, and only when a request actually crosses into or out of the queue.
# Both halves matter: a refresh would reload whatever page the viewer is on,
# including one they are typing into, and sync touches requests far more often
# than it changes how many are waiting.
class QueueBadgeBroadcastTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  setup { @instance = instances(:alpha) }

  def badge_broadcasts = enqueued_jobs.count { it.to_s.include?("queue_badge") }

  test "a new request that lands in the queue updates the badge" do
    assert_difference -> { badge_broadcasts }, 1 do
      @instance.registration_requests.create!(mastodon_account_id: "new-1", username: "newcomer",
        signed_up_at: Time.current, confirmed: true, status: "pending")
    end
  end

  # Hidden from the queue by default, and most never confirm, so counting one
  # would advertise work that is not there.
  test "a request still waiting for email confirmation does not" do
    assert_no_difference -> { badge_broadcasts } do
      @instance.registration_requests.create!(mastodon_account_id: "new-2", username: "unconfirmed",
        signed_up_at: Time.current, confirmed: false, status: "pending")
    end
  end

  test "deciding a request takes it out of the count" do
    request = @instance.registration_requests.awaiting_review.first

    assert_difference -> { badge_broadcasts }, 1 do
      request.update!(status: "approved", resolved_at: Time.current)
    end
  end

  test "confirming an email brings a request into the count" do
    request = @instance.registration_requests.create!(mastodon_account_id: "new-3",
      username: "confirming", signed_up_at: Time.current, confirmed: false, status: "pending")

    assert_difference -> { badge_broadcasts }, 1 do
      request.update!(confirmed: true)
    end
  end

  # The common case by far: sync, claims and the flag rules touch requests
  # constantly without moving any of them in or out of the queue.
  test "a change that leaves the count alone broadcasts nothing" do
    request = @instance.registration_requests.awaiting_review.first

    assert_no_difference -> { badge_broadcasts } do
      request.update!(claimed_by: moderators(:avery), claimed_at: Time.current)
    end
  end

  test "the broadcast replaces the badge alone, and carries the new count" do
    request = @instance.registration_requests.awaiting_review.first
    expected = @instance.registration_requests.awaiting_review.count - 1

    perform_enqueued_jobs only: ->(job) { job.arguments.to_s.include?("queue_badge") } do
      request.update!(status: "rejected", resolved_at: Time.current)
    end

    # Turbo keeps the broadcasting name private; reaching for it is better than
    # rebuilding its format here, and a rename fails this loudly either way.
    stream = Turbo::StreamsChannel.send(:stream_name_from, [ @instance, :queue_badge ])
    raw = broadcasts(stream).last
    assert raw, "expected a broadcast on the badge stream"

    message = JSON.parse(raw)
    assert_includes message, %(action="replace")
    assert_includes message, %(target="queue_badge")
    assert_includes message, expected.to_s
    assert_not_includes message, "refresh"
  end
end
