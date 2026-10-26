require "test_helper"

class RegistrationStats::SeriesTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 10, 26, 12, 30)

  setup do
    @alpha = instances(:alpha)
    @beta = instances(:beta)
  end

  def series(instances, key) = RegistrationStats::Series.new(instances, period: RegistrationStats::Series.period(key), now: NOW)

  test "every hour of the period is a bucket, quiet ones as zero" do
    @alpha.registration_stats.create!(hour: Time.utc(2026, 10, 26, 10), signups: 4, approved: 1)

    s = series([ @alpha ], "48h")

    assert_equal 48, s.buckets.size
    assert_equal Time.utc(2026, 10, 26, 12), s.buckets.last
    assert_equal [ 0, 4, 0, 0 ], s.values["signups"].last(4)
    assert_equal 4, s.total("signups")
  end

  test "longer periods add the hours up into UTC days" do
    @alpha.registration_stats.create!(hour: Time.utc(2026, 10, 25, 1), signups: 2)
    @alpha.registration_stats.create!(hour: Time.utc(2026, 10, 25, 23), signups: 3)

    s = series([ @alpha ], "90d")

    assert_equal 90, s.buckets.size
    assert_equal Time.utc(2026, 10, 25), s.buckets[-2]
    assert_equal [ 5, 0 ], s.values["signups"].last(2)
  end

  test "several instances are summed into one series" do
    hour = Time.utc(2026, 10, 26, 11)
    @alpha.registration_stats.create!(hour:, signups: 2, signalled: 1)
    @beta.registration_stats.create!(hour:, signups: 3, signalled: 1)

    s = series([ @alpha, @beta ], "48h")

    assert_equal 5, s.total("signups")
    assert_equal 2, s.total("signalled")
    assert_equal 2, series([ @alpha ], "48h").total("signups")
  end

  test "hours outside the period are not counted" do
    @alpha.registration_stats.create!(hour: NOW - 3.days, signups: 9)

    assert series([ @alpha ], "48h").empty?
    assert_equal 9, series([ @alpha ], "14d").total("signups")
  end

  test "decisions made in Mastodon count as decided" do
    @alpha.registration_stats.create!(hour: Time.utc(2026, 10, 26, 11), signups: 6,
      approved: 1, approved_elsewhere: 2, rejected: 1, rejected_elsewhere: 1, pending: 1)

    s = series([ @alpha ], "48h")

    assert_equal 3, s.approved
    assert_equal 2, s.rejected
    assert_equal 5, s.decided
  end

  test "an unknown period falls back to the default" do
    assert_equal RegistrationStats::Series::DEFAULT_PERIOD, RegistrationStats::Series.period("sideways").key
  end
end
