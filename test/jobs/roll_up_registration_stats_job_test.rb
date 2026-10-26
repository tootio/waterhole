require "test_helper"

class RollUpRegistrationStatsJobTest < ActiveSupport::TestCase
  # Mid-hour, so "the hour this falls in" and "the hour after" are different.
  NOW = Time.utc(2026, 10, 26, 12, 30)

  setup do
    travel_to NOW
    @alpha = instances(:alpha)
    # Every fixture request into one known hour, so the counts are exact.
    RegistrationRequest.update_all(signed_up_at: NOW - 3.hours)
  end

  def stat(instance, hour) = RegistrationStat.find_by(instance:, hour:)

  def hour = Time.utc(2026, 10, 26, 9)

  test "requests are counted by the hour they signed up in, per instance and status" do
    RollUpRegistrationStatsJob.perform_now

    alpha = stat(@alpha, hour)
    assert_equal @alpha.registration_requests.count, alpha.signups
    assert_equal @alpha.registration_requests.pending.count, alpha.pending
    assert_equal 1, alpha.rejected
    assert_equal instances(:beta).registration_requests.count, stat(instances(:beta), hour).signups
  end

  test "rerunning counts the same, not twice" do
    2.times { RollUpRegistrationStatsJob.perform_now }

    assert_equal 1, RegistrationStat.where(instance: @alpha).count
    assert_equal @alpha.registration_requests.count, stat(@alpha, hour).signups
  end

  test "a decision made after counting is picked up by the next run" do
    RollUpRegistrationStatsJob.perform_now
    registration_requests(:pending_alpha).update_columns(status: "approved")

    RollUpRegistrationStatsJob.perform_now

    assert_equal 1, stat(@alpha, hour).approved
  end

  # registration_requests has a boolean `approved` column, which once turned
  # every count of approvals into true, stored as 1.
  test "more than one approval in an hour is counted as more than one" do
    registration_requests(:pending_alpha).update_columns(status: "approved")
    registration_requests(:claimed_alpha).update_columns(status: "approved")

    RollUpRegistrationStatsJob.perform_now

    assert_equal 2, stat(@alpha, hour).approved
  end

  test "flagged counts warnings and up, signalled only cross-instance flags" do
    registration_requests(:pending_alpha).update_columns(max_flag_severity: Flag::SEVERITIES[:warning])
    registration_requests(:claimed_alpha).update_columns(max_flag_severity: Flag::SEVERITIES[:info])
    registration_requests(:jules_alpha).flags.create!(rule: "email_active_elsewhere", severity: :warning)
    registration_requests(:claimed_alpha).flags.create!(rule: "no_invite_request", severity: :info)

    RollUpRegistrationStatsJob.perform_now

    stats = stat(@alpha, hour)
    assert_equal @alpha.registration_requests.where(max_flag_severity: Flag::SEVERITIES[:warning]..).count, stats.flagged
    assert_equal 1, stats.signalled
  end

  test "hours older than the window are left alone" do
    old = @alpha.registration_stats.create!(hour: NOW - 40.days, signups: 7)
    registration_requests(:pending_alpha).update_columns(signed_up_at: NOW - 40.days)

    RollUpRegistrationStatsJob.perform_now

    assert_equal 7, old.reload.signups
  end

  test "an hour inside the window that has lost its requests is cleared" do
    gone = @alpha.registration_stats.create!(hour: NOW - 5.days, signups: 3)

    RollUpRegistrationStatsJob.perform_now

    assert_not RegistrationStat.exists?(gone.id)
  end

  test "the hour the window starts in is only partly inside it, so it is not recounted" do
    window_start = NOW - RollUpRegistrationStatsJob.window
    partial = @alpha.registration_stats.create!(hour: window_start.beginning_of_hour, signups: 9)

    RollUpRegistrationStatsJob.perform_now

    assert_equal 9, partial.reload.signups
  end

  # Purging goes by resolved_at, so with a short retention a recount reaching
  # further back would find the old requests gone and zero their hours.
  test "the window shrinks with a shorter retention" do
    with_env("WATERHOLE_RETENTION_DAYS" => "7") do
      assert_equal 7.days, RollUpRegistrationStatsJob.window

      counted = @alpha.registration_stats.create!(hour: NOW - 10.days, signups: 4)
      RollUpRegistrationStatsJob.perform_now

      assert_equal 4, counted.reload.signups
    end
  end

  test "a deployment that keeps no decided requests still counts the last day" do
    with_env("WATERHOLE_RETENTION_DAYS" => "0") do
      assert_equal RollUpRegistrationStatsJob::MIN_WINDOW, RollUpRegistrationStatsJob.window

      RollUpRegistrationStatsJob.perform_now

      assert_equal @alpha.registration_requests.count, stat(@alpha, hour).signups
    end
  end

  # Purging a spam wave is the obvious response to one, and must not take the
  # wave out of the chart.
  test "a request purged inside the window is still counted" do
    flagged = registration_requests(:jules_alpha)
    flagged.update_columns(max_flag_severity: Flag::SEVERITIES[:warning])
    flagged.flags.create!(rule: "email_active_elsewhere", severity: :warning)
    RollUpRegistrationStatsJob.perform_now
    before = stat(@alpha, hour).attributes.slice(*RegistrationStat::COUNTERS)

    flagged.purge!
    registration_requests(:rejected_alpha).purge!
    RollUpRegistrationStatsJob.perform_now

    assert_equal before, stat(@alpha, hour).attributes.slice(*RegistrationStat::COUNTERS)
  end

  test "what purged requests left is dropped once their hour leaves the window" do
    old = @alpha.purged_registration_stats.create!(hour: NOW - 40.days, signups: 1)
    recent = @alpha.purged_registration_stats.create!(hour: NOW - 2.days, signups: 1)

    RollUpRegistrationStatsJob.perform_now

    assert_not PurgedRegistrationStat.exists?(old.id)
    assert PurgedRegistrationStat.exists?(recent.id)
  end

  test "a request purged after its hour left the window leaves nothing behind" do
    registration_requests(:rejected_alpha).update_columns(signed_up_at: NOW - 40.days)

    registration_requests(:rejected_alpha).purge!

    assert_empty PurgedRegistrationStat.all
  end

  test "the window never exceeds the maximum, however long the retention" do
    with_env("WATERHOLE_RETENTION_DAYS" => "365") do
      assert_equal RollUpRegistrationStatsJob::MAX_WINDOW, RollUpRegistrationStatsJob.window
    end
  end

  test "a backfill fills older hours but never overwrites them" do
    registration_requests(:pending_alpha).update_columns(signed_up_at: NOW - 60.days)
    registration_requests(:claimed_alpha).update_columns(signed_up_at: NOW - 61.days)
    kept = @alpha.registration_stats.create!(hour: (NOW - 61.days).beginning_of_hour, signups: 5)

    RollUpRegistrationStatsJob.perform_now(since: NOW - 90.days)

    assert_equal 1, stat(@alpha, (NOW - 60.days).beginning_of_hour).signups
    assert_equal 5, kept.reload.signups
  end

  test "starting an instance over clears its stats" do
    RollUpRegistrationStatsJob.perform_now
    registration_requests(:rejected_alpha).purge!

    @alpha.start_over!(actor_public_key: "new key")

    assert_empty @alpha.registration_stats
    assert_empty @alpha.purged_registration_stats
  end

  private

  def with_env(vars)
    previous = vars.keys.index_with { ENV[it] }
    vars.each { ENV[_1] = _2 }
    yield
  ensure
    previous.each { ENV[_1] = _2 }
  end
end
