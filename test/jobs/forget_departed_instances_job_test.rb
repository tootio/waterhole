require "test_helper"

class ForgetDepartedInstancesJobTest < ActiveSupport::TestCase
  setup do
    @instance = instances(:alpha)
    # Fixture helpers look records up again, which fails once they are deleted.
    @avery_id = moderators(:avery).id
    @blake_id = moderators(:blake).id
  end

  test "revoking an instance records when its access ended; verifying clears it" do
    @instance.revoke!(reason: "gone")
    assert_in_delta Time.current, @instance.reload.access_ended_at, 5.seconds

    @instance.update!(status: "verified")
    assert_nil @instance.reload.access_ended_at
  end

  test "everything of an instance gone for longer than the grace is deleted" do
    @instance.revoke!(reason: "gone")
    @instance.update_columns(access_ended_at: (ForgetDepartedInstancesJob::GRACE + 1.day).ago)
    pending = registration_requests(:pending_alpha)
    pending.notes.create!(moderator: moderators(:blake), body: "Goes with its application.")
    @instance.purged_registrations.create!(mastodon_account_id: "old-tombstone")

    ForgetDepartedInstancesJob.perform_now

    assert_empty @instance.registration_requests, "pending applications are no longer synced, so they go"
    assert_empty @instance.purged_registrations.reload, "no sync left to guard against"
    refute Moderator.exists?(@avery_id)
    refute Moderator.exists?(@blake_id), "their notes went with the applications, so nothing keeps them anonymised"
    assert RegistrationRequest.exists?(registration_requests(:other_instance).id), "other instances are untouched"
  end

  test "within the grace nothing happens, so a lapsed record can still be fixed" do
    @instance.revoke!(reason: "gone")
    @instance.update_columns(access_ended_at: (ForgetDepartedInstancesJob::GRACE - 1.day).ago)

    ForgetDepartedInstancesJob.perform_now

    assert Moderator.exists?(@avery_id)
  end

  # No status changes when a terms grace window lapses; its deadline counts.
  test "a lapsed terms grace window counts from its deadline" do
    @instance.update_columns(status: "terms_outdated", terms_grace_until: (ForgetDepartedInstancesJob::GRACE + 1.day).ago)

    ForgetDepartedInstancesJob.perform_now

    refute Moderator.exists?(@avery_id)
  end

  test "moderators of instances that still have access are kept" do
    ForgetDepartedInstancesJob.perform_now

    assert Moderator.exists?(@avery_id)
    assert Moderator.exists?(moderators(:casey).id)
  end
end
