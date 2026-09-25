# Deletes what Waterhole holds about an instance that lost access and has not
# come back within GRACE: revoked, blocked, or past its terms grace window. The
# grace lets a lapsed DNS record or a late terms acceptance be fixed without the
# team losing anything.
#
# Once it has passed, nothing is synced from the instance any more, so its
# pending applications would otherwise stay forever, and the tombstones that
# keep purged ones from being imported again have nothing left to guard. See
# Instance#forget_contents! for what goes.
class ForgetDepartedInstancesJob < ApplicationJob
  queue_as :default

  GRACE = 14.days

  def perform
    Instance.where.not(status: %w[verified unverified]).find_each do |instance|
      ended = instance.access_ended_since
      next if ended.nil? || ended > GRACE.ago

      instance.forget_contents!
    end
  end
end
