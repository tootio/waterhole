# Counts signups per instance and hour into RegistrationStat, so the stats page
# can chart months of history although the requests themselves are purged
# after Waterhole::Deployment.retention.
#
# Each run recounts the recent window from scratch rather than adding to it: a
# request's outcome and flags keep changing after it is counted (a decision, a
# cross-instance match arriving later), and a recount picks that up without
# tracking what changed. Hours older than the window are left as they were and
# so become the long-term record.
#
# A recount sees only the requests still here, plus what purged ones left in
# PurgedRegistrationStat. The window also stays inside the retention period,
# where nothing is purged by age alone -- purging goes by resolved_at, never
# earlier than signed_up_at -- so the recount leans on that record only for
# what a moderator purged by hand. A day at least, though: a deployment that
# keeps no decided requests at all still has signups to count.
class RollUpRegistrationStatsJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, key: "roll_up_registration_stats", on_conflict: :discard

  MIN_WINDOW = 1.day
  MAX_WINDOW = 30.days

  def self.window = [ [ Waterhole::Deployment.retention, MIN_WINDOW ].max, MAX_WINDOW ].min

  # The start of the first whole hour in the window: the hour before it is only
  # partly inside, and counting part of it would replace a complete bucket with
  # a smaller one.
  def self.window_start = whole_hours_from(window.ago)

  def self.whole_hours_from(time)
    hour = time.beginning_of_hour
    hour == time ? hour : hour + 1.hour
  end

  # `since` reaches further back for a backfill. Hours before the window are
  # only filled where they are still empty, never overwritten: by then their
  # requests may be partly purged, and the count made while they were complete
  # is the better one.
  def perform(since: nil)
    now = Time.current
    window_start = self.class.window_start
    since = since ? [ self.class.whole_hours_from(since), window_start ].min : window_start

    RegistrationStat.transaction do
      # Holds off a purge, which records what it removes before it removes it,
      # until both sides are counted -- and a backfill run alongside this,
      # which would insert the same hours.
      RegistrationStat.connection.execute("LOCK TABLE registration_stats, purged_registration_stats IN EXCLUSIVE MODE")

      rows = counts(since).map { |(instance_id, hour), counts| { instance_id:, hour:, **counts, created_at: now, updated_at: now } }
      recent, older = rows.partition { it[:hour] >= window_start }

      RegistrationStat.where(hour: window_start..).delete_all
      PurgedRegistrationStat.where(hour: ...window_start).delete_all
      RegistrationStat.insert_all(recent) if recent.any?
      RegistrationStat.insert_all(older, unique_by: %i[instance_id hour]) if older.any?
    end
  end

  private

  # [instance_id, hour] => { counter => count }, from the requests still here
  # plus what purged ones left behind.
  def counts(since)
    totals = Hash.new { |hash, key| hash[key] = RegistrationStat::COUNTERS.index_with(0) }

    (live_counts(since) + PurgedRegistrationStat.where(hour: since..).map(&:attributes)).each do |row|
      bucket = totals[[ row["instance_id"], row["hour"] ]]
      RegistrationStat::COUNTERS.each { bucket[it] += row[it] }
    end
    totals
  end

  # Built from Arel rather than SQL strings: every name and value here is a
  # constant, but Brakeman cannot tell, and it fails CI on interpolated SQL.
  def live_counts(since)
    requests = RegistrationRequest.arel_table
    hour = Arel::Nodes::NamedFunction.new("date_trunc", [ Arel::Nodes.build_quoted("hour"), requests[:signed_up_at] ])
    signalled = Flag.where(rule: Flags.cross_instance_rules.map(&:rule_name))
      .where(Flag.arel_table[:registration_request_id].eq(requests[:id]))

    # Aliased apart from the counters' names: registration_requests has an
    # `approved` column of its own, and the model would cast a count by that
    # name to a boolean.
    conditions = {
      "signups" => nil,
      **RegistrationStat::OUTCOMES.index_with { requests[:status].eq(it) },
      "flagged" => requests[:max_flag_severity].gteq(Flag::SEVERITIES[:warning]),
      "signalled" => Arel::Nodes::Exists.new(signalled.arel)
    }
    counts = conditions.map do |counter, condition|
      count = Arel.star.count
      (condition ? count.filter(condition) : count).as("#{counter}_count")
    end

    RegistrationRequest.where(signed_up_at: since..)
      .group(:instance_id, hour)
      .select(requests[:instance_id], hour.as("hour"), *counts)
      .map { |row| { "instance_id" => row.instance_id, "hour" => row.hour, **RegistrationStat::COUNTERS.index_with { row["#{it}_count"] } } }
  end
end
