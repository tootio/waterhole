# Refuse to boot a production deployment that is missing a setting, rather than
# failing later on the first encrypted read or, worse, publishing DNS
# instructions for the wrong host. The Docker build precompiles assets in
# production mode with a dummy secret and no configuration, so it is exempt.
#
# after_initialize, not top level: Waterhole::Deployment lives in lib/, which
# is autoloaded, and production cannot autoload while initializers run.
Rails.application.config.after_initialize do
  next unless Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank?

  missing = Waterhole::Deployment.missing_settings
  if missing.any?
    abort <<~MESSAGE
      Waterhole is not configured. Missing: #{missing.join(", ")}

      Copy .env.production.sample to .env.production (or pass the variables to
      the container) and generate the secrets with: bin/rails waterhole:secrets
    MESSAGE
  end
end
