# One browser a moderator enabled push on. Outlives sessions, which last a week
# at most: notifying someone who is not signed in is the whole point.
class PushSubscription < ApplicationRecord
  # The endpoint comes from the browser and Waterhole posts to it from inside its
  # own network, so it has to be one of the services browsers actually use.
  PUSH_SERVICES = {
    "fcm.googleapis.com" => "Google",
    "jmt17.google.com" => "Google",
    "push.apple.com" => "Apple",
    "push.services.mozilla.com" => "Mozilla",
    "notify.windows.com" => "Microsoft"
  }.freeze
  # Its encrypted form has to fit a btree index entry (2704 bytes).
  MAX_ENDPOINT_LENGTH = 1500
  P256 = OpenSSL::PKey::EC::Group.new("prime256v1")
  P256_KEY_BYTES = 65 # uncompressed: 0x04, then both coordinates
  AUTH_BYTES = 16 # RFC 8291

  encrypts :endpoint, deterministic: true
  encrypts :p256dh, :auth

  belongs_to :moderator

  validates :endpoint, presence: true, length: { maximum: MAX_ENDPOINT_LENGTH }, uniqueness: { scope: :moderator_id }
  validate :endpoint_is_a_known_push_service
  validate :keys_can_encrypt

  # How the settings page tells a moderator's browsers apart, without storing
  # anything about the browser beyond what pushing to it needs.
  def push_service
    uri = URI.parse(endpoint.to_s)
    return unless uri.is_a?(URI::HTTPS) && uri.port == 443 && uri.userinfo.nil?

    host = uri.host.to_s.downcase
    PUSH_SERVICES.find { |domain, _| host == domain || host.end_with?(".#{domain}") }&.last
  rescue URI::InvalidURIError
    nil
  end

  # Whether a message can be encrypted for this browser at all.
  def keys_usable?
    key = Base64.urlsafe_decode64(p256dh.to_s)
    # Decoding raises unless the point is on the curve.
    OpenSSL::PKey::EC::Point.new(P256, OpenSSL::BN.new(key, 2))
    key.bytesize == P256_KEY_BYTES && Base64.urlsafe_decode64(auth.to_s).bytesize == AUTH_BYTES
  rescue ArgumentError, OpenSSL::OpenSSLError
    false
  end

  private

  def endpoint_is_a_known_push_service
    errors.add(:endpoint, "is not a known push service") if endpoint.present? && push_service.nil?
  end

  def keys_can_encrypt
    errors.add(:base, "The browser's keys are not usable") unless keys_usable?
  end
end
