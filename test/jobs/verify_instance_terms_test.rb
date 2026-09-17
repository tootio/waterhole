require "test_helper"

# The terms dimension is deliberately orthogonal to the "does the record exist"
# dimension, and these tests pin that separation.
class VerifyInstanceTermsTest < ActiveSupport::TestCase
  setup { @instance = instances(:alpha) }

  def verify(resolver)
    DnsAllowlist.stub_resolver(resolver) { VerifyInstanceJob.perform_now(@instance) }
    @instance.reload
  end

  test "a record accepting the current documents verifies and records the digest" do
    with_legal_documents do
      verify(dns_record(accepted: LegalDocuments.digest))

      assert @instance.verified?
      assert_equal LegalDocuments.digest, @instance.accepted_terms_digest
      assert_nil @instance.terms_grace_until
    end
  end

  test "a record with no accepted leaves an instance that had accepted in grace" do
    with_legal_documents do
      @instance.update!(verified_at: 1.day.ago, accepted_terms_digest: "old" * 16)

      verify(dns_record)

      assert @instance.terms_outdated?
      assert @instance.terms_grace_active?
      assert @instance.admitted?, "grace means it keeps working"
      assert_in_delta 14.days.from_now, @instance.terms_grace_until, 60
    end
  end

  # The counter absorbs non-determinism about whether the record EXISTS. A digest
  # mismatch is computed from a record we successfully read, so the second and
  # third observation carry no new information.
  test "stale terms never touch the revocation strike counter" do
    with_legal_documents do
      @instance.update!(verified_at: 1.day.ago, accepted_terms_digest: "old" * 16)

      10.times { verify(dns_record(accepted: "stale" * 12)) }

      assert_equal 0, @instance.consecutive_verification_failures
      refute @instance.revoked?, "a terms mismatch is not a missing record"
      assert @instance.terms_outdated?
    end
  end

  test "the deadline does not slide on repeated checks" do
    with_legal_documents do
      @instance.update!(verified_at: 1.day.ago, accepted_terms_digest: "old" * 16)

      verify(dns_record)
      first = @instance.terms_grace_until

      travel 2.days do
        verify(dns_record)
        assert_equal first.to_i, @instance.terms_grace_until.to_i,
          "an admin who ignores the banner must not get an endless window"
      end
    end
  end

  # An instance that never accepted anything has nothing to be grandfathered
  # from, and granting it a window would let anyone in for a fortnight simply by
  # publishing a record with no accepted.
  test "an instance that never accepted gets no grace at all" do
    with_legal_documents do
      @instance.update!(verified_at: nil, accepted_terms_digest: nil, status: "unverified")

      verify(dns_record)

      assert @instance.terms_outdated?
      assert_nil @instance.terms_grace_until
      refute @instance.admitted?
    end
  end

  test "expiring the grace ends the team's sessions" do
    with_legal_documents do
      @instance.update!(verified_at: 1.day.ago, accepted_terms_digest: "old" * 16)
      verify(dns_record)
      assert_equal 1, Session.where(moderator: @instance.moderators).count

      travel 15.days do
        verify(dns_record)

        refute @instance.admitted?
        assert @instance.terms_outdated?, "still terms_outdated, NOT revoked -- the record is still published"
        assert_equal 0, Session.where(moderator: @instance.moderators).count
      end
    end
  end

  test "republishing heals it with no operator involvement" do
    with_legal_documents do
      @instance.update!(verified_at: 1.day.ago, accepted_terms_digest: "old" * 16)
      verify(dns_record)
      assert @instance.terms_outdated?

      verify(dns_record(accepted: LegalDocuments.digest))

      assert @instance.verified?
      assert_nil @instance.terms_grace_until
    end
  end

  test "an unreachable resolver neither sets nor clears a deadline" do
    with_legal_documents do
      @instance.update!(verified_at: 1.day.ago, accepted_terms_digest: "old" * 16)
      verify(dns_record)
      deadline = @instance.terms_grace_until

      3.times { verify(dns_unreachable) }

      assert_equal deadline.to_i, @instance.terms_grace_until.to_i
      assert_equal 0, @instance.consecutive_verification_failures
    end
  end

  test "with no documents published the terms gate is inactive" do
    verify(dns_record)

    assert @instance.verified?, "a deployment with no legal documents behaves exactly as before"
    assert_nil @instance.terms_grace_until
  end

  test "a missing record still revokes after three strikes" do
    with_legal_documents do
      3.times { verify(dns_records([])) }

      assert @instance.revoked?, "the terms dimension must not disturb this"
    end
  end
end
