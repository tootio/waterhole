# Waterhole mirrors applicants' emails, IP addresses and their reasons for
# joining, and inherits the instance's obligations over that data. Once a request
# has been resolved long enough that nobody is going to revisit the decision,
# the personal parts go and the audit trail stays.
class PurgeResolvedRequestPiiJob < ApplicationJob
  queue_as :default

  def perform(older_than: Waterhole::Deployment.pii_retention)
    scope = RegistrationRequest.resolved.where(resolved_at: ..older_than.ago)
      .where.not(email: nil)

    scope.find_each do |request|
      # Collected BEFORE clearing: once the identifiers are gone we can no longer
      # find the rows on other instances whose cross-instance flags cite this one.
      # Without this their flags outlive the evidence, still naming a person whose
      # record has been erased.
      counterparts = Flags.cross_instance_rules.flat_map { it.counterparts(request) }.uniq(&:id)

      request.update_columns(
        email: nil,
        email_domain: nil,
        canonical_email_hash: nil,
        ip: nil,
        # Derived from the address, so they outlive their evidence otherwise.
        # ip_group is GENERATED and follows `ip` to NULL on its own -- naming it
        # here would be an error.
        ip_country: nil,
        ip_asn: nil,
        ip_asn_org: nil,
        ip_enriched_at: nil,
        invite_request: nil,
        bio: nil,
        raw: {}
      )
      # Flags derived from the purged fields would otherwise outlive their
      # evidence.
      request.flags.destroy_all
      request.update_columns(flags_count: 0, max_flag_severity: 0)

      counterparts.each { RecomputeFlagsJob.perform_later(it) }
    end
  end
end
