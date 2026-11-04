# Sends one moderator what is due, on a job of its own so that one slow push
# service only delays the browsers behind it.
class SendModeratorPushJob < ApplicationJob
  queue_as :default
  # Behind sync (SyncInstanceJob): a notification can wait for the queue to be current.
  queue_with_priority 20

  # Two at once would count the same requests and send them twice.
  limits_concurrency to: 1, key: ->(moderator) { moderator }, duration: 15.minutes, on_conflict: :discard

  discard_on ActiveJob::DeserializationError

  def perform(moderator)
    preference = moderator.push_preference
    return if preference.nil?

    PushNotifications::Digest.call(preference).each do |due|
      # Its watermarks stay, and the next run counts the same requests. Any further
      # message would only find the same services down.
      break unless due.message.nil? || PushNotifications::Sender.deliver(moderator, due.message)

      preference.update!(due.watermarks)
    end
  end
end
