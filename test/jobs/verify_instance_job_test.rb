require "test_helper"

class VerifyInstanceJobTest < ActiveSupport::TestCase
  setup { @instance = instances(:alpha) }

  def verify_with(resolver)
    DnsAllowlist.stub_resolver(resolver) { VerifyInstanceJob.perform_now(@instance) }
    @instance.reload
  end

  test "a good record keeps the instance verified and clears the failure count" do
    @instance.update!(consecutive_verification_failures: 2)

    verify_with(dns_ok)

    assert @instance.verified?
    assert_equal 0, @instance.consecutive_verification_failures
    assert @instance.verified_at.present?
  end

  test "revokes and signs everyone out after three consecutive authoritative negatives" do
    3.times { verify_with(dns_records([])) }

    assert @instance.revoked?, "the record is genuinely gone, so access should end"
    assert_equal 0, Session.where(moderator: @instance.moderators).count,
      "revocation must actually sign the team out, not just flip a flag"
  end

  test "does not revoke before the third failure" do
    2.times { verify_with(dns_records([])) }

    assert @instance.verified?, "a single bad answer or a mid-edit propagation gap must not lock anyone out"
    assert_equal 2, @instance.consecutive_verification_failures
  end

  test "a success resets the count part-way through" do
    2.times { verify_with(dns_records([])) }
    verify_with(dns_ok)
    2.times { verify_with(dns_records([])) }

    assert @instance.verified?
    assert_equal 2, @instance.consecutive_verification_failures
  end

  # The regression guard for the lock-out scenario.
  test "unreachable DNS never counts towards revocation, however often it happens" do
    5.times { verify_with(dns_unreachable) }

    assert @instance.verified?, "a DNS outage is our problem; it must not revoke a healthy instance"
    assert_equal 0, @instance.consecutive_verification_failures
    assert_equal 1, Session.where(moderator: @instance.moderators).count
  end

  test "a blocked instance is left alone" do
    @instance.update!(status: "blocked")

    verify_with(dns_ok)

    assert @instance.blocked?, "the operator's block outranks a DNS record"
  end
end
