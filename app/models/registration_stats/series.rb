module RegistrationStats
  # One chart's worth of RegistrationStat rows: every counter summed over a set
  # of instances, one bucket per hour or day across a range, with the gaps
  # filled in. A quiet hour must show as a zero, not as an hour that does not
  # exist, or a spam wave and the night before it look the same width.
  class Series
    Period = Data.define(:key, :label, :length, :unit)

    # Hours while there are few enough to tell apart; days after that. Days are
    # UTC days: the rollup only knows UTC hours, and a viewer's local midnight
    # would cut through them.
    PERIODS = [
      Period.new("48h", "48 hours", 48.hours, "hour"),
      Period.new("14d", "14 days", 14.days, "hour"),
      Period.new("90d", "90 days", 90.days, "day"),
      Period.new("1y", "1 year", 365.days, "day")
    ].index_by(&:key).freeze

    DEFAULT_PERIOD = "14d"

    def self.period(key) = PERIODS.fetch(key.to_s, PERIODS.fetch(DEFAULT_PERIOD))

    attr_reader :period, :buckets

    def initialize(instances, period:, now: Time.current)
      @instances = instances
      @period = period
      @step = 1.public_send(period.unit)
      last = now.utc.public_send(:"beginning_of_#{period.unit}")
      @buckets = (0...(period.length / @step)).map { last - it * @step }.reverse
    end

    def hourly? = period.unit == "hour"

    # counter => [value per bucket], in bucket order.
    def values
      @values ||= begin
        rows = sums.index_by { it["bucket"] }
        RegistrationStat::COUNTERS.index_with do |counter|
          buckets.map { rows.dig(it, counter).to_i }
        end
      end
    end

    def total(counter) = values.fetch(counter).sum

    # Approved and rejected count Mastodon's own decisions too: a request
    # someone settled there is no less settled.
    def approved = total("approved") + total("approved_elsewhere")
    def rejected = total("rejected") + total("rejected_elsewhere")
    def decided = approved + rejected

    def empty? = total("signups").zero?

    # What the chart controller draws: timestamps in seconds, as uPlot wants.
    def to_chart
      { unit: period.unit, t: buckets.map(&:to_i), **values }
    end

    private

    # Arel rather than SQL strings, for the same reason as in
    # RollUpRegistrationStatsJob#live_counts.
    def sums
      stats = RegistrationStat.arel_table
      bucket = Arel::Nodes::NamedFunction.new("date_trunc", [ Arel::Nodes.build_quoted(period.unit), stats[:hour] ])

      RegistrationStat.where(instance: @instances, hour: buckets.first...(buckets.last + @step))
        .group(bucket)
        .select(bucket.as("bucket"), *RegistrationStat::COUNTERS.map { stats[it].sum.as(it) })
        .map(&:attributes)
    end
  end
end
