module Flags
  # Queries our own mirror rather than Mastodon's ?ip= lookup: cheap, and no
  # rate-limit exposure.
  class SharedIp < Rule
    def call
      usernames = request.instance.registration_requests
        .same_network_as(request).where.not(id: request.id).limit(6).pluck(:username)
      return nil if usernames.empty?

      detect(:warning, count: usernames.size, usernames:)
    end
  end
end
