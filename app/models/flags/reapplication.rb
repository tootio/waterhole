module Flags
  # Mastodon deletes the account on rejection, so it cannot see that someone
  # rejected last week is back today. Our mirror is the only record of it.
  class Reapplication < Rule
    def call
      return nil if request.canonical_email_hash.blank? && request.ip.blank?

      scope = request.instance.registration_requests
        .where(status: %w[rejected rejected_elsewhere])
        .where.not(id: request.id)

      matches = scope.where(canonical_email_hash: request.canonical_email_hash.presence)
      matches = scope.where(ip: request.ip) if matches.empty? && request.ip.present?
      return nil if matches.empty?

      detect(:critical, count: matches.count,
        matched_on: request.canonical_email_hash.present? ? "email" : "ip")
    end
  end
end
