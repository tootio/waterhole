module Mastodon
  # Is this account allowed to work the registration queue?
  #
  # Mastodon lets ANY user authorise an app for admin:* scopes; it enforces roles
  # only when an admin endpoint is actually called. Waterhole serves the queue
  # from its own mirror, so a successful OAuth sign-in proves nothing about
  # authority -- this check has to happen here, before a session exists.
  module Role
    # Mastodon's UserRole::FLAGS. Listing and approving pending accounts is
    # gated on Manage Users; Administrator implies every permission.
    ADMINISTRATOR = 1 << 0
    MANAGE_USERS  = 1 << 10

    module_function

    # `account` is a verify_credentials payload. Mastodon 4.0+ includes the
    # role and its permission bitmask there; older servers do not, so fall back
    # to asking the admin API itself whether this token may list accounts.
    def can_manage_users?(account, client)
      permissions = account.dig("role", "permissions")
      return probe(client) if permissions.nil?

      bits = Integer(permissions.to_s, exception: false) or return false
      bits.anybits?(ADMINISTRATOR | MANAGE_USERS)
    end

    # A 403 on the index endpoint is unambiguous, unlike on approve/reject.
    def probe(client)
      client.pending_accounts(limit: 1)
      true
    rescue Forbidden
      false
    end
  end
end
