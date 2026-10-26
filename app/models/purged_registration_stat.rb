# What purged requests contributed to an hour that RollUpRegistrationStatsJob
# still recounts. The recount only sees the requests that are still here, so
# without this, purging a spam wave -- the obvious response to one -- would
# take the wave out of the chart within the hour.
#
# Counts only, like RegistrationStat: nothing in here leads back to an applicant.
# Once an hour leaves the recount window its RegistrationStat no longer
# changes, and the job deletes the rows here for it.
class PurgedRegistrationStat < ApplicationRecord
  belongs_to :instance

  def self.record(request)
    return if request.signed_up_at < RollUpRegistrationStatsJob.window_start

    counts = { "signups" => 1, request.status => 1 }
    counts["flagged"] = 1 if request.max_flag_severity >= Flag::SEVERITIES[:warning]
    counts["signalled"] = 1 if request.flags.exists?(rule: Flags.cross_instance_rules.map(&:rule_name))

    upsert({ instance_id: request.instance_id, hour: request.signed_up_at.utc.beginning_of_hour, **counts },
      unique_by: %i[instance_id hour],
      on_duplicate: Arel.sql(counts.keys.map { "#{it} = purged_registration_stats.#{it} + EXCLUDED.#{it}" }.join(", ")),
      record_timestamps: false)
  end
end
