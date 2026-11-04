# Records the email domain's MX hosts and their addresses on a pending request, then
# flags it.
#
# A job rather than part of RegistrationRequests::Enrichment: that reads local
# files, whereas this waits on the network for a domain the applicant chose, and
# a resolver outage must not hold up the sync walking the queue.
#
# One attempt and no retry_on, because sync is the retry: while email_mx_checked_at
# is nil it asks again, once Lookup::FAILURE_BACKOFF has passed if this one failed.
# The same makes the requests already waiting when this shipped catch up by
# themselves.
class LookupMailInfrastructureJob < ApplicationJob
  queue_as :default

  # Behind syncs (10), refresh broadcasts (0) and moderators' push notifications
  # (20): with only a few worker threads, a queue of slow lookups should wait for
  # those rather than delay them.
  queue_with_priority 30

  # Sync can ask again before an earlier job has run, every 5 minutes, so this has
  # to outlast several passes.
  limits_concurrency to: 1, key: ->(request) { request }, duration: 15.minutes, on_conflict: :discard

  # Purged in the meantime.
  discard_on ActiveJob::DeserializationError
  discard_on ActiveRecord::RecordNotFound

  def perform(request)
    return unless request.needs_mail_infrastructure_lookup?

    domain = request.email_domain
    # Sync checks this too, but a burst from one domain queues up before the first fails.
    return if MailInfrastructure::Lookup.recently_failed?(domain)

    found = mail_servers_of(request) or return

    request.with_lock do
      # DNS took a while, and the world moved on: decided, or a new address.
      next unless request.needs_mail_infrastructure_lookup? && request.email_domain == domain

      # Together: a stamp without flags would never be looked at again.
      request.update!(email_mx_hosts: found[:hosts], email_mx_addresses: found[:addresses],
        email_mx_checked_at: Time.current)
      request.recompute_flags!
    end
    # The address changed while DNS answered: its forget ran before the answer was cached.
    MailInfrastructure::Lookup.forget(domain) unless request.email_domain == domain
  rescue ActiveRecord::RecordNotFound
    # Purged while DNS answered, likewise. discard_on takes it from here.
    MailInfrastructure::Lookup.forget(domain) if domain
    raise
  end

  private

  def mail_servers_of(request)
    MailInfrastructure::Lookup.call(request.email_domain)
  rescue *DnsAllowlist::Resolver::ERRORS => e
    # Not e.message: that names the applicant's domain.
    Rails.logger.info("MX lookup failed for request #{request.id}: #{e.class}")
    nil
  end
end
