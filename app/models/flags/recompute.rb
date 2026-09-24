module Flags
  # Runs every rule against a request and reconciles the flags table to the
  # result: stale flags deleted, current ones upserted. Idempotent by design --
  # sync calls it on every pass.
  class Recompute
    def self.call(request) = new(request).call

    def initialize(request) = @request = request

    def call
      changed = false

      @request.transaction do
        # Serialise concurrent recomputes of one request (a job racing the
        # hourly sweep, say): two find_or_initialize_by calls would otherwise
        # both insert the same (request, rule) flag and trip the unique index.
        # Rules are evaluated under the lock so a slower, staler pass can't
        # overwrite a newer one.
        RegistrationRequest.lock.where(id: @request.id).pick(:id)

        detections = Flags.registry.filter_map { |rule| rule.call(@request) }
        by_rule    = detections.index_by(&:rule)

        # Destroy rather than delete_all so flags_count's counter cache stays true.
        @request.flags.where.not(rule: by_rule.keys).find_each do |flag|
          flag.destroy
          changed = true
        end

        by_rule.each_value do |detection|
          flag = @request.flags.find_or_initialize_by(rule: detection.rule)
          flag.severity = detection.severity
          flag.details  = detection.details
          next unless flag.changed?

          flag.save!
          changed = true
        end

        @request.reload
        @request.update_columns(
          max_flag_severity: @request.flags.maximum(:severity) || 0,
          flags_count: @request.flags.count
        )
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
