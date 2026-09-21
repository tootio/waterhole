source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3", ">= 8.1.3.1"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
end

gem "faraday", "~> 2.14"
gem "faraday-retry", "~> 2.4"

# Ruby 3.4 unbundled csv from the default gems; parsing the IFTAS DNI export
# needs it explicitly declared.
gem "csv", "~> 3.3"

gem "webmock", "~> 3.26", group: :test

# Ruby 4.0 bundles json 3.x, which dropped positional options from JSON.parse.
# ActiveSupport 8.1.3.1 still calls `JSON.parse(json, options)` with two
# positional arguments (active_support/json/decoding.rb), so json 3 breaks every
# jsonb column decode. Pinned until Rails supports json 3.
gem "json", "~> 2.21"

gem "kramdown", "~> 2.5"

# Every Waterhole runs the same code, so a deployment is configured entirely
# through ENV -- read from .env.production when not injected by the container.
gem "dotenv", "~> 3.1"

gem "maxmind-db", "~> 1.5", require: "maxmind/db"

gem "faraday-follow_redirects", "~> 0.5.0"

# Error reporting to Sentry or GlitchTip. Inert unless SENTRY_DSN is set; see
# config/initializers/sentry.rb.
gem "sentry-ruby", "~> 7.0"
gem "sentry-rails", "~> 7.0"

# Punycode for internationalised email domains (EmailCanonicalizer), the same
# UTS #46 lookup mapping browsers and Go's idna package use.
gem "simpleidn", "~> 0.3"
