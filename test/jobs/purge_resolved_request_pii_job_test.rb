require "test_helper"

# Waterhole mirrors applicants' emails, IPs and their reasons for joining. It
# inherits the instance's obligations over that data, so it must not keep it
# forever just because it can.
class PurgeResolvedRequestPiiJobTest < ActiveSupport::TestCase
  test "clears personal data from long-resolved requests but keeps the audit trail" do
    request = registration_requests(:rejected_alpha)
    request.update!(resolved_at: 200.days.ago)
    request.recompute_flags!

    PurgeResolvedRequestPiiJob.perform_now

    request.reload
    assert_nil request.email
    assert_nil request.canonical_email_hash
    assert_nil request.ip
    assert_nil request.invite_request
    assert_equal({}, request.raw)
    assert_equal 0, request.flags.count, "flags derived from purged evidence must go too"

    assert_equal "rejected", request.status, "the decision itself is the audit trail and stays"
    assert_equal "rejected_before", request.username
  end

  test "leaves pending requests alone" do
    pending = registration_requests(:pending_alpha)

    PurgeResolvedRequestPiiJob.perform_now

    assert pending.reload.email.present?
  end

  test "leaves recently resolved requests alone" do
    request = registration_requests(:rejected_alpha)
    request.update!(resolved_at: 2.days.ago)

    PurgeResolvedRequestPiiJob.perform_now

    assert request.reload.email.present?, "a decision may still be queried shortly afterwards"
  end
end
