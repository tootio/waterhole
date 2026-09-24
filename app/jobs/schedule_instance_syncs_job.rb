# Fans out to one sync job per admitted instance.
#
# A job class rather than a `command:` string in recurring.yml so it is
# unit-testable and needs no arguments.
#
# The syncs are spread across the interval instead of all starting on the tick:
# five instances at once meant a burst of writes, broadcasts and flag
# recomputes competing for the same few job threads and database connections,
# followed by minutes of nothing.
class ScheduleInstanceSyncsJob < ApplicationJob
  queue_as :default

  # Also the schedule of `sync_instances` in config/recurring.yml, which reads it.
  # Whole minutes: the schedule is written "every N minutes", the form Fugit parses as a cron.
  INTERVAL = 5.minutes

  # Fractional part of the golden ratio: multiplying consecutive integers by it
  # (a Weyl sequence) lands them as far apart as possible, however many there are.
  GOLDEN_RATIO_CONJUGATE = 0.6180339887498949

  # A pure function of the instance's id, so an instance syncs at the same point
  # in every cycle and adding or removing another instance moves nobody else.
  # Ids are sequential, so `id % INTERVAL` would leave five instances within
  # five seconds of each other.
  def self.offset_for(instance)
    ((instance.id * GOLDEN_RATIO_CONJUGATE) % 1 * INTERVAL).floor.seconds
  end

  def perform
    Instance.syncable.find_each do |instance|
      SyncInstanceJob.set(wait: self.class.offset_for(instance)).perform_later(instance)
    end
  end
end
