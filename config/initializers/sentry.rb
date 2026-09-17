# Optional error reporting to Sentry or GlitchTip (which speaks the same
# protocol). Off unless SENTRY_DSN is set.
#
# What gets reported is bugs: anything unexpected that crashes a request or a
# job, plus failures the app survives but an operator should hear about, which
# the code reports with Rails.error.report. What does not is the ordinary
# weather of talking to other people's servers -- an instance offline or rate
# limiting us, a moderator revoking Waterhole or losing their role. Those
# already surface where they belong (flash messages, the instance page, sync
# runs) and would drown the real bugs.
#
# Waterhole holds applicants' emails and IP addresses, so data collection is
# deliberately narrow: an event says where the code broke, not who it was
# handling at the time.
#
# This runs in the initializer body rather than after_initialize: sentry-rails
# only hooks into Active Job and Rails.error if Sentry is already initialized
# when its own after_initialize runs. For the same reason nothing here may
# reference autoloaded code.
dsn = ENV["SENTRY_DSN"].presence
# Tests run with a transport that sends nothing, so they can assert on what
# would be reported (see test/integration/error_reporting_test.rb).
dsn ||= "http://public@sentry.invalid/1" if Rails.env.test?

if dsn
  Sentry.init do |config|
    config.dsn = dsn
    config.environment = ENV["SENTRY_ENVIRONMENT"].presence || Rails.env
    # WATERHOLE_VERSION is baked into release images by the release workflow.
    config.release = ENV["SENTRY_RELEASE"].presence || ENV["WATERHOLE_VERSION"].presence

    # Failures the app survives but an operator should hear about are reported
    # with Rails.error.report; this routes them here. Off by default.
    config.rails.register_error_subscriber = true

    # Expected failures, handled where they happen. Subclasses match too.
    config.excluded_exceptions += %w[
      Mastodon::ConnectionError
      Mastodon::ServerError
      Mastodon::RateLimited
      Mastodon::Unauthorized
      Mastodon::Forbidden
      Mastodon::NotFound
    ]

    # Errors only: tracing would ship SQL and job arguments for every request,
    # and SQL/HTTP breadcrumbs would carry applicant data.
    config.traces_sample_rate = nil
    config.breadcrumbs_logger = []

    # Spelled out rather than left to the SDK's defaults, which have changed
    # between major versions.
    collection = config.data_collection
    collection.user_info = false
    collection.cookies = false
    collection.http_bodies = []
    collection.database_query_data = false
    collection.queues = false
    collection.stack_frame_variables = false
    # Only query parameters whose values are never personal. The queue's
    # `search` is left out on purpose: moderators type applicants' names and
    # addresses into it. Anchored, because the SDK matches plain terms as
    # substrings.
    collection.url_query_params = Sentry::DataCollection::KeyValueCollection.new(
      mode: :allow_list, terms: %w[page sort status claim email flag].map { /\A#{it}\z/ }
    )
    # Referer is the previous page's full URL, `?search=` included.
    collection.http_headers.request.mode = :deny_list
    collection.http_headers.request.terms = Sentry::DataCollection::PII_HEADER_SNIPPETS + %w[referer]
    collection.http_headers.response.mode = :deny_list
    collection.http_headers.response.terms = Sentry::DataCollection::PII_HEADER_SNIPPETS

    if Rails.env.test?
      config.transport.transport_class = Sentry::DummyTransport
      config.background_worker_threads = 0
    end
  end
end
