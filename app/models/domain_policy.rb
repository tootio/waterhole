# The operator's allow/blocklist for this Waterhole deployment.
#
# Default posture is allow-all with a blocklist. Flipping
# WATERHOLE_POLICY_MODE=allowlist_only inverts that.
class DomainPolicy < ApplicationRecord
  KINDS = %w[allowed blocked].freeze

  enum :kind, KINDS.index_by(&:itself), validate: true

  normalizes :domain, with: ->(d) { d.to_s.strip.downcase }

  validates :domain, presence: true, uniqueness: true

  # Exact match, plus suffix match when the entry opts into subdomains.
  scope :matching, ->(domain) {
    domain = domain.to_s.downcase
    where(domain: domain).or(
      where(include_subdomains: true).where("? LIKE '%.' || domain", domain)
    )
  }
end
