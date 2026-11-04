module Flags
  # Runs the rules against a request and reconciles the flags table to the
  # result: stale flags deleted, current ones upserted. Idempotent by design --
  # sync calls it on every pass.
  #
  # A decided request keeps the verdict it was decided on: only the
  # cross-instance rules run again, because those disclose other instances and
  # must be withdrawn when one stops participating. Every other rule can change
  # its mind as the world moves on -- a list refresh, a watchword edit -- and
  # that belongs to the pending queue, not to history.
  class Recompute
    def self.call(request) = new(request).call

    def initialize(request) = @request = request

    def call
      changed = false

      @request.transaction do
        # Serialise concurrent recomputes of one request (a job racing the
        # hourly sweep, say): two passes would otherwise both insert the same
        # (request, rule) flag and trip the unique index. Rules are evaluated
        # under the lock so a slower, staler pass can't overwrite a newer one, and
        # on the row as it is now rather than the caller's copy, which may predate
        # the very write another job just flagged (the hourly sweep's batches do).
        current = RegistrationRequest.lock.find_by(id: @request.id)
        # Purged since the caller loaded it, which a sweep's batch can outlast.
        next unless current

        # The caller's, so that a sweep's preloading still counts.
        current.instance = @request.instance
        stored_counts = [ current.max_flag_severity, current.flags_count ]

        rules      = current.resolved? ? Flags.cross_instance_rules : Flags.registry
        detections = rules.filter_map { |rule| rule.call(current) }
        by_rule    = detections.index_by(&:rule)
        existing   = Flag.where(registration_request_id: @request.id).index_by(&:rule)
        # A decided request's other flags stand as they are. A pending one has
        # none to keep: every rule ran, so the rest are of rules that no longer exist.
        kept       = current.resolved? ? existing.except(*rules.map(&:rule_name)) : {}

        stale = existing.except(*kept.keys, *by_rule.keys).values
        if stale.any?
          Flag.where(id: stale.map(&:id)).delete_all
          changed = true
        end

        by_rule.each_value do |detection|
          flag = existing[detection.rule] || Flag.new(registration_request: @request, rule: detection.rule)
          flag.severity = detection.severity
          flag.details  = detection.details
          next unless flag.changed?

          flag.save!
          changed = true
        end

        # The kept flags and the detections are the table now, so no need to ask
        # it; and no write when nothing moved, which is nearly every sweep pass.
        severities = kept.values.map { Flag.severities.fetch(it.severity) } + detections.map(&:severity)
        counts = [ severities.max || 0, severities.size ]
        if counts == stored_counts
          @request.assign_attributes(max_flag_severity: counts[0], flags_count: counts[1])
          @request.clear_attribute_changes(%i[max_flag_severity flags_count])
        else
          @request.update_columns(max_flag_severity: counts[0], flags_count: counts[1])
        end
        @request.flags.reset
      end

      # A recompute driven from elsewhere -- a counterpart on another instance,
      # or the hourly sweep -- changes what moderators see without touching the
      # request itself, so nothing else would tell open queues to refresh. Only
      # when something changed: the sweep recomputes hundreds of rows an hour.
      @request.broadcast_refresh_later if changed

      @request
    end
  end
end
