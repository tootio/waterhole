module Flags
  # Mastodon deletes the account on rejection, so it cannot see that someone
  # rejected last week is back today. Our mirror is the only record of it, for
  # as long as it keeps the rejection (Waterhole::Deployment.retention).
  #
  # The same canonical address is `critical` if any matched rejection had it
  # confirmed: that is the person. If none did it is only `warning`, because
  # nobody ever proved that address was theirs: with Mastodon's "postpone
  # confirmation emails" no mail goes out before approval, so anyone can sign up
  # with a stranger's address, get rejected, and leave the real owner looking like
  # the one who was rejected. Those rejections still count, as on such an instance
  # they are nearly all there is. `confirmed` stops being updated at a decision, so
  # a late confirmation can read as unverified; that errs towards the milder flag.
  #
  # The same network is only `warning`: one rejected spammer behind a carrier NAT
  # or a campus network would otherwise mark every later applicant from there as
  # critical.
  class Reapplication < Rule
    def call
      confirmed = email_matches

      if confirmed.include?(true)
        detect(:critical, count: confirmed.size, matched_on: "email")
      elsif confirmed.present?
        detect(:warning, count: confirmed.size, matched_on: "email", address_verified: false)
      elsif (count = network_matches).positive?
        detect(:warning, count:, matched_on: "ip")
      end
    end

    private

    # Whether each matching rejection had its address confirmed.
    def email_matches
      return [] if request.canonical_email_hash.blank?

      rejected.where(canonical_email_hash: request.canonical_email_hash).pluck(:confirmed)
    end

    def network_matches = rejected.same_network_as(request).count

    def rejected
      request.instance.registration_requests
        .where(status: %w[rejected rejected_elsewhere])
        .where.not(id: request.id)
    end
  end
end
