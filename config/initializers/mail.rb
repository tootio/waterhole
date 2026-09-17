# Outgoing mail, configured like Mastodon's through SMTP_* variables (see
# .env.production.sample). Optional: without SMTP_SERVER nothing is ever sent,
# and the notifications that would have been are skipped rather than queued.
#
# after_initialize, because Waterhole::Deployment lives in autoloaded lib/.
# Setting ActionMailer::Base directly works however late or early the mailers
# themselves load. Tests keep the :test delivery method.
Rails.application.config.after_initialize do
  next if Rails.env.test? || !Waterhole::Deployment.smtp_configured?

  ActionMailer::Base.delivery_method = :smtp
  ActionMailer::Base.smtp_settings = Waterhole::Deployment.smtp_settings
  ActionMailer::Base.raise_delivery_errors = true
end
