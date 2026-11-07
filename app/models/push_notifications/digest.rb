module PushNotifications
  # What one moderator should be told right now, and how far that gets them.
  #
  # Counts only: a message passes through the browser vendor's push service, so
  # it never names an applicant, nor the instance.
  #
  # Each kind counts the requests that crossed a line since it last ran, so a
  # request is announced once however often this runs, and time lost to downtime
  # is made up rather than skipped. A request that was resolved before the
  # moderator would have heard of it simply no longer counts.
  class Digest
    # A kind that is due. Its message is nil when there is nothing to say, and its
    # watermarks apply once the message is dealt with.
    Due = Data.define(:message, :watermarks)

    # A request is stamped just before its transaction commits. Staying behind the
    # clock means a run can't pass the stamp of one it doesn't see yet.
    COMMIT_MARGIN = 30.seconds

    def self.call(preference, now: Time.current) = new(preference, now).call

    def self.due?(preference, now: Time.current) = new(preference, now).due?

    def initialize(preference, now)
      @preference = preference
      @clock = now
      @now = now - COMMIT_MARGIN
    end

    def call = [ (new_registrations if new_due?), (forgotten_registrations if forgotten_due?) ].compact

    def due? = new_due? || forgotten_due?

    private

    def new_registrations
      count = crossed(@preference.new_scope, @preference.new_checked_at, @now).count
      Due.new(
        message: (Message.new_registrations(count, waiting: requests(@preference.new_scope).count, **addressing(@preference.new_scope)) if count.positive?),
        watermarks: { new_checked_at: @now }
      )
    end

    # The cursor is on the requests' own timeline rather than derived from the
    # threshold, and never goes back: raising the threshold must not remind anyone
    # twice, and lowering it reminds about whatever it newly covers.
    def forgotten_registrations
      through = @now - @preference.forgotten_after_days.days
      count = crossed(@preference.forgotten_scope, @preference.forgotten_through, through).count
      Due.new(
        message: (Message.forgotten_registrations(count, days: @preference.forgotten_after_days, **addressing(@preference.forgotten_scope)) if count.positive?),
        watermarks: { forgotten_checked_at: @now, forgotten_through: [ @preference.forgotten_through, through ].max }
      )
    end

    # Outside the moderator's hours the watermark stays put, so the first run
    # inside them tells of everything held back, in one message.
    #
    # When to run goes by the real clock, so hours from 14:00 open on the 14:00
    # run. A watermark sits COMMIT_MARGIN behind the run that set it: hourly asks
    # whether that run was in an earlier hour, or a run at 14:00:05 would leave
    # 13:59:35 and the 14:05 run would count as the next hour.
    def new_due?
      case @preference.new_frequency
      when "every_5_minutes" then @preference.notify_at?(@clock)
      when "hourly" then @preference.notify_at?(@clock) && @preference.new_checked_at + COMMIT_MARGIN < @clock.beginning_of_hour
      when "daily" then daily_due?(@preference.new_checked_at)
      else false
      end
    end

    # Not one notification per request crossing the line over the day: that would
    # be a push every few minutes about people nobody forgot yet. Daily, like the
    # summary, and at the same time, so it can't wake anyone either.
    def forgotten_due?
      @preference.forgotten_on? && daily_due?(@preference.forgotten_checked_at)
    end

    def daily_due?(watermark)
      @latest_daily ||= @preference.latest_daily_time(@now)
      @latest_daily > watermark && (@preference.daily_held_until.nil? || @latest_daily >= @preference.daily_held_until)
    end

    # The queue hides sign-ups waiting for confirmation unless asked, and they
    # may be all there is to see here.
    def addressing(scope)
      { audience: @preference.moderator_id, path: scope == "awaiting" ? "/" : "/?email=any" }
    end

    # The lower bound belongs to the previous run, which counted it.
    def crossed(scope, from, to)
      column = scope == "awaiting" ? :awaiting_since : :pending_since
      requests(scope).where(RegistrationRequest.arel_table[column].gt(from)).where(column => ..to)
    end

    def requests(scope)
      all = RegistrationRequest.where(instance_id: @preference.moderator.instance_id)
      scope == "awaiting" ? all.awaiting_review : all.pending
    end
  end
end
