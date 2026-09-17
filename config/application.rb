require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# A deployment is configured through ENV, not through Rails credentials or edits
# to config/environments: every Waterhole runs the same checked-in code, so
# nothing that differs between deployments may live in the repository.
#
# Outside containers ENV comes from .env.<environment>, the Mastodon convention
# (.env.production.sample lists every setting). .env.development and .env.test
# are committed and hold throwaway keys only. Variables already present in ENV
# always win over the files. The plain .env is deliberately not read, so an
# operator's file can never leak into the test suite.
Dotenv::Rails.files = [
  (".env.#{Rails.env}.local" unless Rails.env.test?),
  ".env.#{Rails.env}"
].compact

module Waterhole
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Keys for encrypted columns (access tokens, client secrets, emails).
    # Generate with bin/rails waterhole:secrets. Losing them makes that data
    # unrecoverable, and changing the deterministic key breaks email lookups.
    config.active_record.encryption.primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
    config.active_record.encryption.deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"]
    config.active_record.encryption.key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]

    # Refuse to silently read unencrypted values from encrypted columns.
    config.active_record.encryption.support_unencrypted_data = false

    # Never let OAuth secrets reach the logs.
    config.filter_parameters += [ :access_token, :client_secret, :code ]


    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
