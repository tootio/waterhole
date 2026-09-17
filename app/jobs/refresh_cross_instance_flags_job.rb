# The safety net under the event-driven cross-instance refresh.
#
# Most changes reach the other side as they happen (see
# RegistrationRequest#refresh_cross_instance_counterparts and the Instance
# status hook). One cannot: an instance leaves the participating set when its
# terms grace simply runs out, and no record changes when time passes. So this
# recomputes, hourly and after any participation change:
#
#   - every pending request on a participating instance, which may gain or
#     lose a match, and
#   - every request still carrying a cross-instance flag, wherever it is, since
#     its flag may now cite an instance that no longer participates.
#
# A few hundred rows at the scale Waterhole is sized for; Flags::Recompute only
# writes and broadcasts where something actually changed.
class RefreshCrossInstanceFlagsJob < ApplicationJob
  queue_as :default

  # Instance status changes arrive in bursts (a terms change marks every
  # instance at once), and one sweep covers them all.
  limits_concurrency to: 1, key: "refresh_cross_instance_flags", on_conflict: :discard

  def perform
    rules = Flags.cross_instance_rules.map(&:rule_name)

    RegistrationRequest.pending.where(instance: Instance.participating)
      .or(RegistrationRequest.where(id: Flag.where(rule: rules).select(:registration_request_id)))
      .includes(:instance)
      .find_each(&:recompute_flags!)
  end
end
