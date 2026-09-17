# Sign-in checks a moderator's Mastodon role once. Reading the queue never asks
# Mastodon again, so without this a moderator who was demoted, or who revoked
# Waterhole in their Mastodon settings, would keep seeing applicants' data for
# as long as their session lasted. Also sweeps sessions that have expired.
class VerifyModeratorsJob < ApplicationJob
  queue_as :default

  def perform
    Session.terminate_all(Session.expired)

    Moderator.token_usable.joins(:instance).merge(Instance.syncable).find_each do |moderator|
      VerifyModeratorJob.perform_later(moderator)
    end
  end
end
