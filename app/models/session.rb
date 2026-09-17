# Database-backed so revocation is real: destroying the row signs the moderator
# out everywhere on their next request.
#
# Sessions expire on two clocks. Re-signing in is one OAuth round trip that
# Mastodon usually approves without a prompt, so both can be short: a session is
# a window onto applicants' personal data, and it should not outlive the
# moderator's attention or their role.
class Session < ApplicationRecord
  ABSOLUTE_LIFETIME = 7.days
  IDLE_TIMEOUT      = 24.hours
  # last_active_at is only as precise as this, so a busy moderator does not
  # cost a write on every request.
  ACTIVITY_RESOLUTION = 5.minutes

  belongs_to :moderator

  delegate :instance, to: :moderator

  before_validation(on: :create) { self.last_active_at ||= Time.current }

  scope :expired, -> {
    where(created_at: ...ABSOLUTE_LIFETIME.ago).or(where(last_active_at: ...IDLE_TIMEOUT.ago))
  }

  # Every bulk sign-out comes through here: delete_all skips callbacks, and the
  # live Turbo Stream sockets opened under these sessions must close too, or
  # new notes keep arriving in a tab whose session is gone.
  def self.terminate_all(relation)
    ids = relation.ids
    where(id: ids).delete_all
    ids.each { disconnect_cable(it) }
  end

  def self.disconnect_cable(id)
    ActionCable.server.remote_connections.where(session_id: id).disconnect(reconnect: false)
  end

  def terminate!
    destroy!
    self.class.disconnect_cable(id)
  end

  def expires_at = [ created_at + ABSOLUTE_LIFETIME, last_active_at + IDLE_TIMEOUT ].min

  def expired? = expires_at.past?

  def record_activity!
    return if last_active_at > ACTIVITY_RESOLUTION.ago

    update_column(:last_active_at, Time.current)
  end
end
