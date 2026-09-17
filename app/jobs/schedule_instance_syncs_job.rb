# Fans out to one sync job per admitted instance.
#
# A job class rather than a `command:` string in recurring.yml so it is
# unit-testable and needs no arguments.
class ScheduleInstanceSyncsJob < ApplicationJob
  queue_as :default

  def perform
    Instance.syncable.find_each do |instance|
      SyncInstanceJob.perform_later(instance)
    end
  end
end
