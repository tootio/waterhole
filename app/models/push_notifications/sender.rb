require "web-push"

module PushNotifications
  # Hands a message to the push service of each of a moderator's browsers.
  class Sender
    # A stuck push service must not hold a job worker, or a moderator's click on
    # "Send a test notification".
    TIMEOUT = 5
    # An older count is no use: the next digest counts anyway.
    TIME_TO_LIVE = 1.day.to_i

    TEMPORARY_ERRORS = [
      WebPush::TooManyRequests, WebPush::PushServiceError,
      SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, IOError,
      Net::ProtocolError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError
    ].freeze

    # Whether this message is dealt with: some browser took it, or none is left to
    # take it. False means try again next time. Once one browser has it a retry
    # would repeat it there, so another browser's bad moment costs that browser
    # this message.
    def self.deliver(moderator, message)
      results = moderator.push_subscriptions.reload.map { deliver_to(it, message) }
      results.include?(:delivered) || results.all?(:gone)
    end

    # :delivered, :gone (the subscription was removed) or :failed. Never raises: one
    # browser's trouble must not cost the others their message.
    def self.deliver_to(subscription, message)
      return gone(subscription) unless subscription.push_service && subscription.keys_usable?

      WebPush.payload_send(
        message: message.to_json,
        endpoint: subscription.endpoint,
        p256dh: subscription.p256dh,
        auth: subscription.auth,
        vapid: {
          subject: Waterhole::Deployment.base_url,
          public_key: Waterhole::Deployment.vapid_public_key,
          private_key: Waterhole::Deployment.vapid_private_key
        },
        ttl: TIME_TO_LIVE,
        open_timeout: TIMEOUT, read_timeout: TIMEOUT
      )
      :delivered
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
      gone(subscription)
    rescue WebPush::Unauthorized => e
      # The subscription is tied to a key pair we no longer sign with, and retrying
      # can't change that. Reported the once, since the row goes with it: if the
      # operator didn't mean to change the keys, they need to hear.
      Rails.error.report(e, handled: true, context: { push_service: subscription.push_service })
      gone(subscription)
    rescue *TEMPORARY_ERRORS => e
      # A push service having a bad moment: the next run tries again.
      Rails.logger.info("Push to #{subscription.push_service} failed: #{e.class}")
      :failed
    rescue StandardError => e
      # An oversized payload or a malformed VAPID key: ours to fix.
      Rails.error.report(e, handled: true, context: { push_service: subscription.push_service })
      :failed
    end

    def self.gone(subscription)
      subscription.destroy!
      :gone
    end
    private_class_method :gone
  end
end
