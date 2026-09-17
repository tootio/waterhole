require "test_helper"

# Cross-instance flags live on OTHER instances' requests, so every change that
# affects a match has to reach them. These are the paths that used to leave the
# other side stale until its own request happened to change.
class CrossInstanceRefreshTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def email_flag(request) = request.reload.flags.find_by(rule: "email_active_elsewhere")
  def ip_flag(request) = request.reload.flags.find_by(rule: "ip_active_elsewhere")

  def request_on(instance, id, ip)
    instance.registration_requests.create!(mastodon_account_id: id, username: "u#{id}",
      signed_up_at: 1.hour.ago, ip:, invite_request: "A sufficiently long reason to join.")
  end

  setup do
    @alpha_jules = registration_requests(:jules_alpha)
    @beta_jules  = registration_requests(:jules_beta)
    [ @alpha_jules, @beta_jules ].each(&:recompute_flags!)
    assert email_flag(@beta_jules), "precondition: the shared address flags both sides"
  end

  test "rejecting a request clears the flag it caused on the other instance" do
    perform_enqueued_jobs { @alpha_jules.update!(status: "rejected", resolved_at: Time.current) }

    assert_nil email_flag(@beta_jules), "a rejected applicant is no longer active anywhere"
  end

  test "approval keeps the request active, so nothing needs refreshing" do
    assert_no_enqueued_jobs(only: RecomputeFlagsJob) do
      @alpha_jules.update!(status: "approved", resolved_at: Time.current)
    end
  end

  # A pending user can sign in, and Mastodon then reports the new address.
  test "moving to a new network releases the requests that matched the old one" do
    a = request_on(instances(:alpha), "9101", "192.0.2.50")
    b = request_on(instances(:beta), "9102", "192.0.2.50")
    [ a, b ].each(&:recompute_flags!)
    assert ip_flag(b)

    perform_enqueued_jobs { a.update!(ip: "198.51.100.9") }

    assert_nil ip_flag(b), "the old network's counterparts must be found, not only the new one's"
  end

  test "a new signup flags the existing request on the other instance" do
    a = request_on(instances(:alpha), "9103", "192.0.2.60")
    a.recompute_flags!
    assert_nil ip_flag(a)

    perform_enqueued_jobs { request_on(instances(:beta), "9104", "192.0.2.60") }

    assert ip_flag(a)
  end

  test "an instance that stops participating stops seeing and being seen" do
    perform_enqueued_jobs { instances(:beta).update!(status: "revoked") }

    assert_nil email_flag(@alpha_jules), "must not cite an instance that left"
    assert_nil Flags::EmailActiveElsewhere.call(@beta_jules.reload),
      "a revoked instance no longer contributes, so it must not see"
  end

  test "participation changes queue the sweep, unrelated updates do not" do
    assert_enqueued_with(job: RefreshCrossInstanceFlagsJob) do
      instances(:beta).update!(signals_approved: false)
    end
    assert_no_enqueued_jobs(only: RefreshCrossInstanceFlagsJob) do
      instances(:beta).update!(title: "Renamed")
    end
  end

  # Nothing changes when a grace period simply runs out, so no event can fire.
  # Only the hourly sweep catches it.
  test "the sweep catches a terms grace that ran out" do
    instances(:beta).update_columns(status: "terms_outdated", terms_grace_until: 1.minute.ago)

    RefreshCrossInstanceFlagsJob.perform_now

    assert_nil email_flag(@alpha_jules)
    assert_nil email_flag(@beta_jules)
  end

  test "a recompute that changes nothing does not refresh open queues" do
    refreshes = 0
    @beta_jules.define_singleton_method(:broadcast_refresh_later) { refreshes += 1 }

    @beta_jules.recompute_flags!
    assert_equal 0, refreshes, "the hourly sweep would otherwise refresh every open queue"

    @alpha_jules.update_columns(status: "rejected")
    @beta_jules.recompute_flags!
    assert_equal 1, refreshes
  end
end
