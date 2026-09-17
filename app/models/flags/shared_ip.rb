module Flags
  # Queries our own mirror rather than Mastodon's ?ip= lookup: cheap, and no
  # rate-limit exposure.
  class SharedIp < Rule
    def call
      return nil if request.ip_group.blank?

      # Grouped, not exact: IPv6 hosts in one household rotate their low bits, so
      # exact matching would make housemates invisible to this rule.
      others = request.instance.registration_requests
        .where(ip_group: request.ip_group).where.not(id: request.id).limit(6)
      return nil if others.empty?

      detect(:warning, count: others.size, usernames: others.map(&:username))
    end
  end
end
