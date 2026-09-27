module Flags
  # Mastodon deletes the account on rejection, so it cannot see that someone
  # rejected last week is back today. Our mirror is the only record of it, for
  # as long as it keeps the rejection (Waterhole::Deployment.retention).
  #
  # The same canonical address is `critical`: that is the person. The same
  # network is only `warning`: one rejected spammer behind a carrier NAT or a
  # campus network would otherwise mark every later applicant from there as
  # critical.
  class Reapplication < Rule
    def call
      if (count = email_matches).positive?
        detect(:critical, count:, matched_on: "email")
      elsif (count = network_matches).positive?
        detect(:warning, count:, matched_on: "ip")
      end
    end

    private

    def email_matches
      return 0 if request.canonical_email_hash.blank?

      rejected.where(canonical_email_hash: request.canonical_email_hash).count
    end

    def network_matches = rejected.same_network_as(request).count

    def rejected
      request.instance.registration_requests
        .where(status: %w[rejected rejected_elsewhere])
        .where.not(id: request.id)
    end
  end
end
