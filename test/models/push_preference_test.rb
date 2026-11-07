require "test_helper"

class PushPreferenceTest < ActiveSupport::TestCase
  setup { @moderator = moderators(:avery) }

  def preference(**attributes) = PushPreference.new(moderator: @moderator, **attributes)

  test "the chosen time round-trips and only a real time is accepted" do
    record = preference(daily_time: "21:45")
    assert_equal 21 * 60 + 45, record.daily_at
    assert_equal "21:45", record.daily_time
    assert record.valid?

    [ "24:00", "12:60", "soon", "" ].each do |bad|
      refute preference(daily_time: bad).valid?, "#{bad.inspect} should be invalid"
    end
    assert_nil preference(daily_time: "soon").daily_time

    assert_equal "07:30", preference(daily_time: "07:30:00").daily_time
  end

  test "notification hours are both blank or both real, different times" do
    record = preference(notify_from_time: "14:00", notify_until_time: "04:00:00")
    assert record.valid?
    assert_equal [ 14 * 60, 4 * 60 ], [ record.notify_from, record.notify_until ]
    assert_equal [ "14:00", "04:00" ], [ record.notify_from_time, record.notify_until_time ]

    assert preference(notify_from_time: "", notify_until_time: "").valid?
    assert preference(notify_from_time: "23:58", notify_until_time: "00:03").valid?, "five minutes across midnight"

    {
      [ "14:00", "" ] => /both a start and an end/,
      [ "", "04:00" ] => /both a start and an end/,
      [ "09:00", "09:00" ] => /at least 5 minutes/,
      [ "12:01", "12:04" ] => /at least 5 minutes/,
      [ "soon", "" ] => /“Only from” must be a time of day/,
      [ "04:00", "24:00" ] => /“Until” must be a time of day/,
      [ "later", "soon" ] => /“Only from” and “Until” must be a time of day/
    }.each do |(from, to), message|
      record = preference(notify_from_time: from, notify_until_time: to)
      refute record.valid?, "#{from.inspect} to #{to.inspect} should be invalid"
      assert_match message, record.errors.full_messages.to_sentence
    end
  end

  test "correcting an unreadable time clears its error" do
    record = preference(notify_from_time: "soon", notify_until_time: "04:00")
    record.notify_from_time = "14:00"
    assert record.valid?
  end

  test "notification hours include the start, exclude the end, and may run past midnight" do
    day = preference(time_zone: "Europe/Berlin", notify_from_time: "08:00", notify_until_time: "20:00") # UTC+2 in May
    assert day.notify_at?(Time.utc(2026, 5, 10, 6, 0))
    assert day.notify_at?(Time.utc(2026, 5, 10, 17, 59))
    refute day.notify_at?(Time.utc(2026, 5, 10, 18, 0))
    refute day.notify_at?(Time.utc(2026, 5, 10, 5, 59))

    night = preference(notify_from_time: "14:00", notify_until_time: "04:00")
    assert night.notify_at?(Time.utc(2026, 5, 10, 14, 0))
    assert night.notify_at?(Time.utc(2026, 5, 10, 23, 30))
    assert night.notify_at?(Time.utc(2026, 5, 11, 3, 59))
    refute night.notify_at?(Time.utc(2026, 5, 11, 4, 0))
    refute night.notify_at?(Time.utc(2026, 5, 11, 13, 59))

    assert preference.notify_at?(Time.utc(2026, 5, 11, 3, 0)), "around the clock without hours"
  end

  test "an unknown time zone falls back to UTC instead of losing the form" do
    assert_equal "UTC", preference(time_zone: "Mars/Olympus").time_zone
    assert_equal "Asia/Kolkata", preference(time_zone: "Asia/Kolkata").time_zone
    assert_equal "UTC", preference(time_zone: nil).time_zone
  end

  test "turning a kind on starts counting from then" do
    record = travel_to(3.days.ago) { preference(new_frequency: "off").tap(&:save!) }

    freeze_time
    record.update!(new_frequency: "hourly", forgotten_after_days: 3)
    assert_equal Time.current, record.new_checked_at
    assert_equal Time.current, record.forgotten_checked_at
  end

  test "changing other settings keeps the watermarks" do
    record = travel_to(3.days.ago) { preference(forgotten_after_days: 3).tap(&:save!) }

    assert_no_changes -> { [ record.reload.new_checked_at, record.forgotten_checked_at ] } do
      record.update!(new_frequency: "daily", forgotten_after_days: 7, daily_time: "09:00")
    end
  end

  test "the latest daily time uses the moderator's zone" do
    record = preference(time_zone: "Asia/Tokyo", daily_time: "09:00") # 00:00 UTC

    assert_equal Time.utc(2026, 5, 10, 0, 0), record.latest_daily_time(Time.utc(2026, 5, 10, 0, 0))
    assert_equal Time.utc(2026, 5, 9, 0, 0), record.latest_daily_time(Time.utc(2026, 5, 9, 23, 59))
  end

  test "the latest daily time is never in the future, even when DST skips it past midnight" do
    record = preference(time_zone: "America/Nuuk", daily_time: "23:30")
    now = Time.utc(2026, 3, 29, 1, 10) # 00:10 on Sunday, before the skipped slot's 00:30

    assert_operator record.latest_daily_time(now), :<=, now
  end
end
