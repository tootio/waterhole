module ApplicationCable
  # Turbo Stream sockets carry the same data as the pages that open them, so
  # they need the same session. Without this any connection was accepted, and
  # one opened before a session ended outlived it.
  #
  # Identified by session id so Session.terminate_all can close exactly the
  # sockets a sign-out, expiry or revocation leaves behind.
  class Connection < ActionCable::Connection::Base
    identified_by :session_id

    def connect
      session = Session.includes(moderator: :instance).find_by(id: cookies.signed[:session_id])
      reject_unauthorized_connection unless session && !session.expired? && session.instance.admitted? &&
        session.moderator.consent_current?

      self.session_id = session.id
    end
  end
end
