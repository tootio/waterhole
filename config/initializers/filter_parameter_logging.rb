# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # A browser's push subscription: whoever holds these can message that browser.
  # Only this "auth", since a bare :auth would partially match far too much.
  :endpoint, :p256dh, /\Apush_subscription\.auth\z/
]
