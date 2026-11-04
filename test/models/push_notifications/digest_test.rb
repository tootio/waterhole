require "test_helper"

module PushNotifications
  class DigestTest < ActiveSupport::TestCase
    include PushTestHelper

    setup do
      @moderator = moderators(:avery)
      @instance = @moderator.instance
      @instance.registration_requests.update_all(status: "approved")
    end

    def preference(at:, **attributes)
      travel_to(at) do
        PushPreference.create!(moderator: @moderator, **{ new_frequency: "every_5_minutes" }.merge(attributes))
      end
    end

    def bodies(record, now) = Digest.call(record, now:).filter_map(&:message).map(&:body)

    # What SendModeratorPushJob does after a successful send.
    def run_at(record, now)
      digest = Digest.call(record, now:)
      digest.each { record.update!(it.watermarks) }
      digest.filter_map(&:message).map(&:body)
    end

    test "counts what arrived since the watermark, once" do
      start = Time.utc(2026, 5, 10, 12, 0)
      record = preference(at: start)
      travel_to(start + 2.minutes) { 2.times { waiting_request(@instance) } }

      assert_equal [ "2 new registrations are waiting" ], run_at(record, start + 5.minutes)
      assert_empty run_at(record, start + 10.minutes)
    end

    test "says it in the singular" do
      start = Time.utc(2026, 5, 10, 12, 0)
      record = preference(at: start)
      travel_to(start + 2.minutes) { waiting_request(@instance) }

      assert_equal [ "1 new registration is waiting" ], bodies(record, start + 5.minutes)
    end

    test "nothing fires for the backlog at opt-in" do
      start = Time.utc(2026, 5, 10, 12, 0)
      travel_to(start - 20.days) { waiting_request(@instance) }
      travel_to(start - 1.hour) { waiting_request(@instance) }
      record = preference(at: start, forgotten_after_days: 3, daily_time: "13:00")

      assert_empty bodies(record, start + 5.minutes)
      assert_empty bodies(record, start + 90.minutes)
    end

    test "scope decides whether unconfirmed sign-ups count, and a late confirmer is new when confirmed" do
      start = Time.utc(2026, 5, 10, 12, 0)
      awaiting = preference(at: start)
      everyone = PushPreference.new(moderator: moderators(:blake), new_frequency: "every_5_minutes", new_scope: "all_pending",
        new_checked_at: start, forgotten_checked_at: start)
      unconfirmed = travel_to(start + 1.minute) { waiting_request(@instance, confirmed: false) }

      assert_empty bodies(awaiting, start + 5.minutes)
      assert_equal [ "1 new registration is waiting" ], bodies(everyone, start + 5.minutes)

      run_at(awaiting, start + 5.minutes)
      travel_to(start + 7.minutes) { unconfirmed.update!(confirmed: true) }
      assert_equal [ "1 new registration is waiting" ], bodies(awaiting, start + 10.minutes)
    end

    test "a request resolved before anyone was told does not count" do
      start = Time.utc(2026, 5, 10, 12, 0)
      record = preference(at: start)
      travel_to(start + 1.minute) { waiting_request(@instance).update!(status: "rejected_elsewhere") }

      assert_empty bodies(record, start + 5.minutes)
    end

    test "other instances' requests never count" do
      start = Time.utc(2026, 5, 10, 12, 0)
      record = preference(at: start)
      travel_to(start + 1.minute) { waiting_request(instances(:beta)) }

      assert_empty bodies(record, start + 5.minutes)
    end

    test "off is never due" do
      start = Time.utc(2026, 5, 10, 12, 0)
      record = preference(at: start, new_frequency: "off")
      travel_to(start + 1.minute) { waiting_request(@instance) }

      refute Digest.due?(record, now: start + 2.days)
    end

    test "hourly waits for the hour to turn, and downtime loses nothing" do
      start = Time.utc(2026, 5, 10, 12, 10)
      record = preference(at: start, new_frequency: "hourly")
      travel_to(start + 1.minute) { waiting_request(@instance) }

      refute Digest.due?(record, now: Time.utc(2026, 5, 10, 12, 59))
      assert_equal [ "1 new registration is waiting" ], run_at(record, Time.utc(2026, 5, 10, 13, 2))
      assert_empty run_at(record, Time.utc(2026, 5, 10, 13, 55))

      travel_to(Time.utc(2026, 5, 10, 13, 56)) { waiting_request(@instance) }
      assert_equal [ "1 new registration, 2 waiting in all" ], run_at(record, Time.utc(2026, 5, 11, 2, 0))
    end

    test "daily arrives at the moderator's chosen time, in their zone" do
      start = Time.utc(2026, 5, 10, 12, 0)
      record = preference(at: start, new_frequency: "daily", daily_time: "21:30", time_zone: "America/New_York") # 01:30 UTC
      travel_to(start + 1.minute) { waiting_request(@instance) }

      refute Digest.due?(record, now: Time.utc(2026, 5, 11, 1, 29))
      assert_equal [ "1 new registration is waiting" ], run_at(record, Time.utc(2026, 5, 11, 1, 32))
      refute Digest.due?(record, now: Time.utc(2026, 5, 12, 1, 29))
      assert Digest.due?(record, now: Time.utc(2026, 5, 12, 1, 31))
    end

    test "moving the daily time later does not send a second one that day" do
      start = Time.utc(2026, 5, 9, 12, 0)
      record = preference(at: start, new_frequency: "daily", daily_time: "07:00")
      travel_to(start + 1.minute) { waiting_request(@instance) }
      assert_equal [ "1 new registration is waiting" ], run_at(record, Time.utc(2026, 5, 10, 7, 2))

      travel_to(Time.utc(2026, 5, 10, 8, 0)) { waiting_request(@instance) }
      travel_to(Time.utc(2026, 5, 10, 8, 0)) { record.update!(daily_time: "09:00") }

      refute Digest.due?(record, now: Time.utc(2026, 5, 10, 9, 2))
      assert_equal [ "1 new registration, 2 waiting in all" ], run_at(record, Time.utc(2026, 5, 11, 9, 2))
    end

    test "moving the time holds nothing back when nothing daily was on" do
      start = Time.utc(2026, 5, 10, 6, 0)
      record = preference(at: start, new_frequency: "hourly", daily_time: "07:00")
      travel_to(Time.utc(2026, 5, 10, 8, 0)) do
        waiting_request(@instance)
        record.update!(new_frequency: "daily", daily_time: "09:00")
      end

      assert_equal 1, bodies(record, Time.utc(2026, 5, 10, 9, 2)).size
    end

    test "moving to a zone whose slot is hours away arrives there the same day" do
      start = Time.utc(2026, 5, 9, 12, 0)
      record = preference(at: start, new_frequency: "daily", daily_time: "07:00", time_zone: "Europe/Berlin")
      travel_to(start + 1.minute) { waiting_request(@instance) }
      assert_equal 1, run_at(record, Time.utc(2026, 5, 10, 5, 2)).size

      travel_to(Time.utc(2026, 5, 10, 8, 0)) do
        record.update!(time_zone: "Asia/Tokyo")
        waiting_request(@instance)
      end
      assert_equal 1, bodies(record, Time.utc(2026, 5, 10, 22, 2)).size
    end

    test "a daily time DST skips past midnight is not sent early, and the next day's still arrives" do
      # America/Nuuk jumps from 23:00 to 00:00 at 01:00 UTC on 29 March 2026, so
      # Saturday's 23:30 falls at 00:30 on Sunday, and Sunday has its own 23:30.
      start = Time.utc(2026, 3, 27, 12, 0)
      record = preference(at: start, new_frequency: "daily", daily_time: "23:30", time_zone: "America/Nuuk")
      assert_empty run_at(record, Time.utc(2026, 3, 28, 1, 32))

      travel_to(Time.utc(2026, 3, 28, 2, 0)) { waiting_request(@instance) }
      refute Digest.due?(record, now: Time.utc(2026, 3, 29, 1, 10))
      assert_equal 1, run_at(record, Time.utc(2026, 3, 29, 1, 35)).size

      travel_to(Time.utc(2026, 3, 29, 2, 0)) { waiting_request(@instance) }
      assert_equal 1, run_at(record, Time.utc(2026, 3, 30, 0, 35)).size
    end

    test "a daily time that DST skips still arrives, once" do
      # Europe/Berlin jumps from 02:00 to 03:00 on 29 March 2026.
      start = Time.utc(2026, 3, 28, 12, 0)
      record = preference(at: start, new_frequency: "daily", daily_time: "02:30", time_zone: "Europe/Berlin")
      travel_to(start + 1.minute) { waiting_request(@instance) }

      assert_equal [ "1 new registration is waiting" ], run_at(record, Time.utc(2026, 3, 29, 1, 35))
      travel_to(Time.utc(2026, 3, 29, 1, 40)) { waiting_request(@instance) }
      refute Digest.due?(record, now: Time.utc(2026, 3, 29, 12, 0))
    end

    test "a daily time that DST repeats arrives once" do
      # Europe/Berlin goes back from 03:00 to 02:00 on 25 October 2026, so 02:30
      # happens at both 00:30 and 01:30 UTC.
      start = Time.utc(2026, 10, 24, 12, 0)
      record = preference(at: start, new_frequency: "daily", daily_time: "02:30", time_zone: "Europe/Berlin")
      travel_to(start + 1.minute) { waiting_request(@instance) }

      assert_equal [ "1 new registration is waiting" ], run_at(record, Time.utc(2026, 10, 25, 0, 32))
      travel_to(Time.utc(2026, 10, 25, 1, 0)) { waiting_request(@instance) }
      refute Digest.due?(record, now: Time.utc(2026, 10, 25, 1, 32))
    end

    test "a forgotten request reminds once, at the daily time" do
      start = Time.utc(2026, 5, 10, 6, 0)
      record = preference(at: start, new_frequency: "off", forgotten_after_days: 3, daily_time: "07:00")
      travel_to(start + 1.hour) { waiting_request(@instance) } # 3 days old at 07:00 on the 13th

      assert_empty run_at(record, Time.utc(2026, 5, 13, 6, 58))
      assert_equal [ "1 registration has been waiting for over 3 days" ], run_at(record, Time.utc(2026, 5, 13, 7, 2))
      assert_empty run_at(record, Time.utc(2026, 5, 14, 7, 2))
      assert_empty run_at(record, Time.utc(2026, 5, 15, 7, 2))
    end

    test "raising the threshold does not remind twice, lowering it reminds about what it now covers" do
      start = Time.utc(2026, 5, 10, 6, 0)
      record = preference(at: start, new_frequency: "off", forgotten_after_days: 3, daily_time: "07:00")
      travel_to(start + 1.hour) { waiting_request(@instance) }
      assert_equal 1, run_at(record, Time.utc(2026, 5, 13, 7, 2)).size

      record.update!(forgotten_after_days: 7)
      assert_empty run_at(record, Time.utc(2026, 5, 17, 7, 2))
      assert_empty run_at(record, Time.utc(2026, 5, 18, 7, 2))
    end

    test "lowering the threshold reminds about what it now covers" do
      start = Time.utc(2026, 5, 10, 6, 0)
      record = preference(at: start, new_frequency: "off", forgotten_after_days: 7, daily_time: "07:00")
      travel_to(start + 1.hour) { waiting_request(@instance) }
      assert_empty run_at(record, Time.utc(2026, 5, 14, 7, 2))

      record.update!(forgotten_after_days: 3)

      assert_equal [ "1 registration has been waiting for over 3 days" ], run_at(record, Time.utc(2026, 5, 15, 7, 2))
      assert_empty run_at(record, Time.utc(2026, 5, 16, 7, 2))
    end

    test "says how many wait in all, once that is more than the new ones" do
      start = Time.utc(2026, 5, 10, 12, 0)
      record = preference(at: start)
      travel_to(start + 1.minute) { 2.times { waiting_request(@instance) } }
      run_at(record, start + 5.minutes)
      travel_to(start + 6.minutes) { waiting_request(@instance) }

      assert_equal [ "1 new registration, 3 waiting in all" ], run_at(record, start + 10.minutes)
    end

    test "all pending opens the queue that shows them, and announces one listed again" do
      start = Time.utc(2026, 5, 10, 12, 0)
      request = travel_to(start - 2.days) { waiting_request(@instance, confirmed: false, status: "rejected_elsewhere") }
      record = preference(at: start, new_scope: "all_pending")
      travel_to(start + 1.minute) { request.update!(status: "pending") }

      message = Digest.call(record, now: start + 5.minutes).first.message
      assert_equal "1 new registration is waiting", message.body
      assert_equal "#{Waterhole::Deployment.base_url}/?email=any", JSON.parse(message.to_json).dig("notification", "navigate")
    end

    test "a request stamped moments ago waits for the next run" do
      start = Time.utc(2026, 5, 10, 12, 0)
      record = preference(at: start)
      travel_to(start + 5.minutes - 10.seconds) { waiting_request(@instance) }

      assert_empty run_at(record, start + 5.minutes)
      assert_equal 1, run_at(record, start + 10.minutes).size
    end

    test "forgotten scope decides whether unconfirmed sign-ups count" do
      start = Time.utc(2026, 5, 10, 6, 0)
      record = preference(at: start, new_frequency: "off", forgotten_after_days: 1, daily_time: "07:00")
      travel_to(start + 1.minute) { waiting_request(@instance, confirmed: false) }

      assert_empty bodies(record, Time.utc(2026, 5, 11, 7, 2))
      record.forgotten_scope = "all_pending"
      assert_equal [ "1 registration has been waiting for over 1 day" ], bodies(record, Time.utc(2026, 5, 11, 7, 2))
    end

    test "claimed requests still count as forgotten" do
      start = Time.utc(2026, 5, 10, 6, 0)
      record = preference(at: start, new_frequency: "off", forgotten_after_days: 1, daily_time: "07:00")
      travel_to(start + 1.minute) { waiting_request(@instance, claimed_by: @moderator, claimed_at: start) }

      assert_equal 1, bodies(record, Time.utc(2026, 5, 11, 7, 2)).size
    end
  end
end
