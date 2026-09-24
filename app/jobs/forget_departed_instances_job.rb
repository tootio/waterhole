# Deletes what Waterhole holds about an instance that lost access and has not
# come back within GRACE: revoked, blocked, or past its terms grace window. The
# grace lets a lapsed DNS record or a late terms acceptance be fixed without the
# team losing anything.
#
# Once it has passed, nothing is synced from the instance any more, so its
# pending applications would otherwise stay forever, and the tombstones that
# keep purged ones from being imported again have nothing left to guard. So, in
# this order:
#
#   1. its applications are purged, with their notes, votes, flags and decisions,
#   2. its tombstones go (should it return, sync simply starts afresh),
#   3. its moderators are forgotten -- deleted outright, since step 1 removed
#      the notes, decisions and votes that would otherwise keep them anonymised.
class ForgetDepartedInstancesJob < ApplicationJob
  queue_as :default

  GRACE = 14.days

  def perform
    Instance.where.not(status: %w[verified unverified]).find_each do |instance|
      ended = instance.access_ended_since
      next if ended.nil? || ended > GRACE.ago

      instance.registration_requests.find_each(&:purge!)
      instance.purged_registrations.delete_all
      instance.moderators.remembered.find_each(&:forget!)
    end
  end
end
