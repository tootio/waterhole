require "test_helper"

class PurgeTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @instance = instances(:alpha)
    @applicant = registration_requests(:pending_alpha)
    sign_in_as moderators(:avery)
  end

  test "a moderator purges a request with everything about it" do
    @applicant.notes.create!(moderator: moderators(:blake), body: "Looks fine.")
    @applicant.votes.create!(moderator: moderators(:blake), vote: "approve")

    post registration_request_purge_path(@applicant)

    assert_redirected_to root_path
    refute RegistrationRequest.exists?(@applicant.id)
    assert_equal 0, Note.where(registration_request_id: @applicant.id).count
    assert_equal 0, Vote.where(registration_request_id: @applicant.id).count
    get registration_request_path(@applicant)
    assert_response :not_found
  end

  # Mastodon still lists the account as pending; sync must not bring it back.
  test "a purged request is not imported again" do
    post registration_request_purge_path(@applicant)
    @instance.update!(sync_moderator: moderators(:avery))
    stub_pending_accounts(@instance, accounts: pending_account_payloads(@instance) + [
      admin_account_payload(id: @applicant.mastodon_account_id, username: @applicant.username)
    ])

    SyncInstanceJob.perform_now(@instance)

    refute @instance.registration_requests.exists?(mastodon_account_id: @applicant.mastodon_account_id)
  end

  # The retention job leaves the same tombstone.
  test "a request purged after retention is not imported again either" do
    @applicant.update_columns(status: "rejected", resolved_at: 1.year.ago)
    PurgeResolvedRequestsJob.perform_now
    @instance.update!(sync_moderator: moderators(:avery))
    stub_pending_accounts(@instance, accounts: pending_account_payloads(@instance) + [
      admin_account_payload(id: @applicant.mastodon_account_id, username: @applicant.username)
    ])

    SyncInstanceJob.perform_now(@instance)

    refute @instance.registration_requests.exists?(mastodon_account_id: @applicant.mastodon_account_id)
  end

  test "purging refreshes the cross-instance flags it caused elsewhere" do
    jules_alpha = registration_requests(:jules_alpha)
    jules_beta = registration_requests(:jules_beta)
    jules_beta.recompute_flags!
    assert jules_beta.reload.flags.exists?(rule: "email_active_elsewhere")

    perform_enqueued_jobs { post registration_request_purge_path(jules_alpha) }

    refute jules_beta.reload.flags.exists?(rule: "email_active_elsewhere")
  end

  test "another instance's request cannot be purged" do
    other = registration_requests(:other_instance)

    post registration_request_purge_path(other)

    assert_response :not_found
    assert RegistrationRequest.exists?(other.id)
  end
end
