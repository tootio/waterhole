# Client for the Mastodon admin API.
#
# This file is the explicit namespace for app/clients/mastodon/, and holds the
# error hierarchy so every constant resolves without a file-per-exception.
module Mastodon
  Error = Class.new(StandardError)

  ConnectionError = Class.new(Error)   # timeout, DNS, TLS
  Unauthorized    = Class.new(Error)   # 401: the token is dead
  NotFound        = Class.new(Error)   # 404: account deleted (rejection deletes users)
  Unprocessable   = Class.new(Error)   # 422
  ServerError     = Class.new(Error)   # 5xx

  # 403 from Mastodon is AMBIGUOUS: the same status and body come back when the
  # account is no longer pending AND when the moderator's role lacks "Manage
  # Users". Callers must disambiguate with a follow-up read; never retry blindly.
  # See Mastodon::DecisionOutcome.
  Forbidden = Class.new(Error)

  class RateLimited < Error
    attr_reader :reset_at

    def initialize(message = "rate limited", reset_at: nil)
      @reset_at = reset_at
      super(message)
    end

    def retry_after
      return 60.seconds if reset_at.blank?

      [ reset_at - Time.current, 1.second ].max
    end
  end
end
