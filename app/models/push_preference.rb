# What one moderator wants to hear about, on every browser they enabled. Sending
# needs a PushSubscription as well, so a row alone notifies nobody.
class PushPreference < ApplicationRecord
  NEW_FREQUENCIES = %w[off every_5_minutes hourly daily].freeze
  SCOPES = %w[awaiting all_pending].freeze
  FORGOTTEN_AFTER_DAYS = [ 1, 2, 3, 7, 14 ].freeze
  MINUTES_IN_A_DAY = 24 * 60
  # After moving the daily time or zone: a new slot this soon after the old one
  # would be today's notification a second time.
  RESCHEDULE_GAP = 6.hours
  DISPATCH_EVERY_MINUTES = ScheduleInstanceSyncsJob::INTERVAL.in_minutes.to_i

  belongs_to :moderator

  enum :new_frequency, NEW_FREQUENCIES.index_by(&:itself), prefix: :new, validate: true
  enum :new_scope, SCOPES.index_by(&:itself), prefix: :new, validate: true
  enum :forgotten_scope, SCOPES.index_by(&:itself), prefix: :forgotten, validate: true

  # Comes from the browser, and an unknown zone must not lose the whole form.
  normalizes :time_zone, with: ->(zone) { ActiveSupport::TimeZone[zone.to_s] ? zone : "UTC" }, apply_to_nil: true

  validates :forgotten_after_days, inclusion: { in: FORGOTTEN_AFTER_DAYS }, allow_nil: true
  validates :daily_at, numericality: { only_integer: true, in: 0...MINUTES_IN_A_DAY }
  validate :notify_window_complete

  before_validation :start_counting_from_now
  before_save :hold_daily_after_rescheduling

  def self.for(moderator)
    moderator.push_preference || moderator.build_push_preference
  end

  def forgotten_on? = forgotten_after_days.present?

  # The most recent moment the clock in this moderator's zone showed daily_at.
  # At a local time a DST change skips, this is the hour after; at one it repeats,
  # always the first of the two.
  def latest_daily_time(now) = latest_slot(now, zone, daily_at)

  def daily_time = time_from_minutes(daily_at)

  def daily_time=(value)
    self.daily_at = minutes_from_time(value)
  end

  # Every 5 minutes and hourly only: daily already picks its own time. Both blank
  # means around the clock.
  def notify_from_time = time_from_minutes(notify_from)
  def notify_until_time = time_from_minutes(notify_until)

  def notify_from_time=(value)
    self.notify_from = window_minutes("“Only from”", value)
  end

  def notify_until_time=(value)
    self.notify_until = window_minutes("“Until”", value)
  end

  def notify_window? = notify_from.present? && notify_until.present?

  # From notify_from up to, not including, notify_until, on the wall clock in this
  # moderator's zone, so a DST change moves the hours with the clock. A start
  # after the end runs across midnight.
  def notify_at?(now)
    return true unless notify_window?

    local = now.in_time_zone(zone)
    minute = (local.hour * 60) + local.min
    notify_from < notify_until ? minute.in?(notify_from...notify_until) : !minute.in?(notify_until...notify_from)
  end

  # Enabling the first browser, after any time without one: what piled up in the
  # meantime is not news, and opting in must not start with a flood.
  def rearm
    now = Time.current
    self.new_checked_at = now
    restart_forgotten(now)
  end

  private

  def zone = ActiveSupport::TimeZone[time_zone]

  # The form's "HH:MM", which is what a time input submits; some browsers add
  # seconds. Anything else is nil.
  def minutes_from_time(value)
    hours, minutes = value.to_s.match(/\A(\d{2}):(\d{2})(?::\d{2})?\z/)&.captures&.map(&:to_i)
    hours && hours < 24 && minutes < 60 ? (hours * 60) + minutes : nil
  end

  def time_from_minutes(minutes) = minutes && format("%02d:%02d", minutes / 60, minutes % 60)

  # Blank is a choice here, so input that is not a time must not read as one:
  # it is remembered for validation rather than saved as around the clock.
  def window_minutes(label, value)
    @unreadable_window_times ||= {}
    minutes = minutes_from_time(value)
    @unreadable_window_times[label] = value.present? && minutes.nil?
    minutes
  end

  # Walks back because the slot of the day before can be in the future as well: a
  # skipped 23:30 falls after midnight.
  def latest_slot(now, zone, minutes)
    date = now.in_time_zone(zone).to_date
    loop do
      slot = zone.local(date.year, date.month, date.day, minutes / 60, minutes % 60)
      return slot if slot <= now

      date -= 1
    end
  end

  # Shorter hours could fall between two runs of DispatchPushNotificationsJob
  # and never notify at all.
  def notify_window_complete
    unreadable = (@unreadable_window_times || {}).select { |_, bad| bad }.keys
    if unreadable.any?
      errors.add(:base, "#{unreadable.to_sentence} must be a time of day")
    elsif notify_from.nil? != notify_until.nil?
      errors.add(:base, "Give both a start and an end time, or neither for around the clock")
    elsif notify_window? && (notify_until - notify_from) % MINUTES_IN_A_DAY < DISPATCH_EVERY_MINUTES
      errors.add(:base, "Notification hours must be at least #{DISPATCH_EVERY_MINUTES} minutes long; leave both blank for around the clock")
    end
  end

  def start_counting_from_now
    now = Time.current
    self.new_checked_at = now if new_checked_at.nil? || new_frequency_changed?(from: "off")
    restart_forgotten(now) if forgotten_checked_at.nil? || forgotten_after_days_changed?(from: nil)
  end

  def restart_forgotten(now)
    self.forgotten_checked_at = now
    self.forgotten_through = now - forgotten_after_days.days if forgotten_on?
  end

  # Moving the time later makes the new slot look due, when that moderator has
  # already had today's. Nothing to hold back if nothing daily was on.
  def hold_daily_after_rescheduling
    return unless persisted? && (daily_at_changed? || time_zone_changed?)
    return unless new_frequency_in_database == "daily" || forgotten_after_days_in_database

    previous = latest_slot(Time.current, ActiveSupport::TimeZone[time_zone_in_database], daily_at_in_database)
    self.daily_held_until = previous + RESCHEDULE_GAP
  end
end
