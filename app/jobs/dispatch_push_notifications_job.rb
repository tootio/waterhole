# Runs every five minutes, as often as a queue can change (ScheduleInstanceSyncsJob).
# Finds who could be notified and whose time has come: most moderators, most of
# the time, are waiting for the next hour or day and don't need a job to say so.
class DispatchPushNotificationsJob < ApplicationJob
  queue_as :default

  def perform
    moderators = Moderator.token_usable.joins(:instance, :push_preference).includes(:push_preference)
      .merge(Instance.syncable).where(id: PushSubscription.select(:moderator_id))

    moderators.find_each do |moderator|
      next unless moderator.consent_current? && PushNotifications::Digest.due?(moderator.push_preference)

      SendModeratorPushJob.perform_later(moderator)
    end
  end
end
