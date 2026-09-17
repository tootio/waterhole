require "test_helper"

# Waterhole mirrors applicants' emails, IPs and their reasons for joining, and
# keeps none of it longer than the decision needs: a decided request is deleted
# with everything attached once the retention period has passed.
class PurgeResolvedRequestsJobTest < ActiveSupport::TestCase
  test "deletes long-decided requests with their notes, flags and decision" do
    request = registration_requests(:rejected_alpha)
    request.update!(resolved_at: 200.days.ago)
    request.recompute_flags!
    note = request.notes.create!(moderator: moderators(:avery), body: "Spam, obviously.")
    note.replies.create!(registration_request: request, moderator: moderators(:blake), body: "Agreed.")

    PurgeResolvedRequestsJob.perform_now

    refute RegistrationRequest.exists?(request.id)
    assert_equal 0, Note.where(registration_request_id: request.id).count
    assert_equal 0, Flag.where(registration_request_id: request.id).count
    assert request.instance.purged_registrations.exists?(mastodon_account_id: request.mastodon_account_id),
      "only the account ID stays, so sync never imports it again"
  end

  test "leaves pending requests alone" do
    pending = registration_requests(:pending_alpha)

    PurgeResolvedRequestsJob.perform_now

    assert RegistrationRequest.exists?(pending.id)
  end

  test "leaves recently decided requests alone" do
    request = registration_requests(:rejected_alpha)
    request.update!(resolved_at: 2.days.ago)

    PurgeResolvedRequestsJob.perform_now

    assert RegistrationRequest.exists?(request.id), "a decision may still be queried shortly afterwards"
  end
end
