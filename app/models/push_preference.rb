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

  belongs_to :moderator

  enum :new_frequency, NEW_FREQUENCIES.index_by(&:itself), prefix: :new, validate: true
  enum :new_scope, SCOPES.index_by(&:itself), prefix: :new, validate: true
  enum :forgotten_scope, SCOPES.index_by(&:itself), prefix: :forgotten, validate: true

  # Comes from the browser, and an unknown zone must not lose the whole form.
  normalizes :time_zone, with: ->(zone) { ActiveSupport::TimeZone[zone.to_s] ? zone : "UTC" }, apply_to_nil: true

  validates :forgotten_after_days, inclusion: { in: FORGOTTEN_AFTER_DAYS }, allow_nil: true
  validates :daily_at, numericality: { only_integer: true, in: 0...MINUTES_IN_A_DAY }

  before_validation :start_counting_from_now
  before_save :hold_daily_after_rescheduling

  def self.for(moderator)
    moderator.push_preference || moderator.build_push_preference
  end

  def forgotten_on? = forgotten_after_days.present?

  # The most recent moment the clock in this moderator's zone showed daily_at.
  # At a local time a DST change skips, this is the hour after; at one it repeats,
  # always the first of the two.
  def latest_daily_time(now) = latest_slot(now, ActiveSupport::TimeZone[time_zone], daily_at)

  # The form's "HH:MM", which is what a time input submits.
  def daily_time = daily_at && format("%02d:%02d", daily_at / 60, daily_at % 60)

  # Some browsers submit seconds as well.
  def daily_time=(value)
    hours, minutes = value.to_s.match(/\A(\d{2}):(\d{2})(?::\d{2})?\z/)&.captures&.map(&:to_i)
    self.daily_at = hours && minutes < 60 ? (hours * 60) + minutes : nil
  end

  # Enabling the first browser, after any time without one: what piled up in the
  # meantime is not news, and opting in must not start with a flood.
  def rearm
    now = Time.current
    self.new_checked_at = now
    restart_forgotten(now)
  end

  private

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
