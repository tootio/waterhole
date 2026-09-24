# A decided request is deleted -- with its notes, votes, flags and decision -- once
# the retention period has passed (WATERHOLE_RETENTION_DAYS, default 90).
# Nobody revisits a decision that old, and Waterhole has no reason to keep an
# applicant's data longer than the decision needs it.
class PurgeResolvedRequestsJob < ApplicationJob
  queue_as :default

  def perform(older_than: Waterhole::Deployment.retention)
    RegistrationRequest.resolved.where(resolved_at: ..older_than.ago).find_each(&:purge!)
  end
end
