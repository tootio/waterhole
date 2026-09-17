module Instances
  # Applies one DnsAllowlist result to an instance.
  #
  # Extracted so the hourly job and the sign-in path share exactly one set of
  # transitions: a freshly signed-in instance must record which terms it accepted,
  # and duplicating that here and in VerifyInstanceJob is how the two drift.
  class ApplyVerification
    # Revoke only after this many CONSECUTIVE authoritative negatives, so a single
    # bad answer or a mid-propagation edit doesn't lock anyone out.
    FAILURES_BEFORE_REVOCATION = 3

    def self.call(instance, result) = new(instance, result).call

    def initialize(instance, result)
      @instance = instance
      @result = result
    end

    def call
      @instance.verification_checked_at = Time.current

      case @result.outcome
      when :verified        then mark_verified
      when :terms_outdated  then mark_terms_outdated
      when :not_allowlisted then count_failure
      when :ambiguous       then count_failure
      when :unreachable     then note_unreachable
      else
        # A new outcome silently reported as "unreachable" would turn a
        # deterministic, admin-fixable refusal into "a problem on our side" and
        # would never set a deadline. Fail loudly instead.
        raise ArgumentError, "unknown DnsAllowlist outcome: #{@result.outcome.inspect}"
      end

      @instance
    end

    private

    def mark_verified
      @instance.update!(
        status: "verified",
        verified_at: Time.current,
        consecutive_verification_failures: 0,
        accepted_terms_digest: @result.accepted_terms,
        signals_opted_in: @result.signals,
        terms_stale_since: nil,
        terms_grace_until: nil,
        verification_detail: @result.detail,
        verification_checked_at: @instance.verification_checked_at
      )
    end

    # A record IS published for us, but it accepts different terms.
    #
    # Deliberately does NOT touch consecutive_verification_failures: that counter
    # exists to absorb network flakes, and this is a deterministic answer read
    # from a record we successfully fetched. The grace window is the buffer here,
    # and stacking three hourly strikes on top of fourteen days is just noise.
    def mark_terms_outdated
      new_target = @result.accepted_terms != @instance.accepted_terms_digest

      if !@instance.ever_accepted_terms?
        # Grace is for instances losing access to terms they HAD accepted.
        # Granting it to one that never accepted would let anyone in for a
        # fortnight by publishing a record with no accepted= value at all.
        @instance.terms_stale_since ||= Time.current
        @instance.terms_grace_until = nil
      elsif !@instance.terms_outdated? || @instance.terms_grace_until.blank? || new_target
        # The deadline tracks the CURRENT digest: if the documents changed again
        # the admin's target moved, so the clock restarts against the new one.
        @instance.terms_stale_since = Time.current
        @instance.terms_grace_until = Time.current + Waterhole::Deployment.terms_grace_period
      end

      @instance.assign_attributes(
        status: "terms_outdated",
        accepted_terms_digest: @result.accepted_terms,
        signals_opted_in: @result.signals,
        consecutive_verification_failures: 0,
        verification_detail: @result.detail
      )
      @instance.save!

      return unless @instance.terms_grace_expired?

      # Locked out now; end the sessions rather than leaving the team to discover
      # it one request at a time.
      Session.terminate_all(Session.where(moderator: @instance.moderators))
    end

    # A missing record, or several contradicting ones: either way no single
    # record says what the admin wants. Access survives a few strikes -- a
    # republish often has old and new records up side by side for minutes --
    # and ends after that, so the problem cannot be left standing.
    def count_failure
      failures = @instance.consecutive_verification_failures + 1
      @instance.consecutive_verification_failures = failures
      @instance.verification_detail = @result.detail
      # Consent to signals goes at once when no record is read. With several
      # records it stays as it was: which one we read first is chance, and
      # following it would flip participation from one check to the next.
      @instance.signals_opted_in = false unless @result.ambiguous?

      @instance.save!
      return unless failures >= FAILURES_BEFORE_REVOCATION && !@instance.revoked?

      name = "#{DnsAllowlist::PREFIX}.#{@instance.domain}"
      @instance.revoke!(reason: @result.ambiguous? ? "#{name} has more than one different record for this Waterhole." : "DNS record for #{name} is no longer published.")
    end

    # Deliberately does NOT touch the failure counter, the status, or any terms
    # deadline. A resolver failure says nothing about what is published.
    def note_unreachable
      @instance.update!(verification_detail: @result.detail,
        verification_checked_at: @instance.verification_checked_at)
    end
  end
end
