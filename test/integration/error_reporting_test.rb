require "test_helper"
require "sentry/test_helper"

# What reaches Sentry/GlitchTip, and what stays out. The configuration under
# test is config/initializers/sentry.rb, which the test environment always
# loads with a transport that sends nothing.
class ErrorReportingTest < ActiveJob::TestCase
  include Sentry::TestHelper

  setup do
    setup_sentry_test
    @instance = instances(:alpha)
    @instance.update!(sync_moderator: moderators(:avery))
  end

  teardown { teardown_sentry_test }

  def with_broken_mapper
    mapper = RegistrationRequests::Mapper.singleton_class
    mapper.alias_method :original_call, :call
    mapper.define_method(:call) { |_| raise TypeError, "String does not have #dig method" }
    yield
  ensure
    mapper.alias_method :call, :original_call
    mapper.remove_method :original_call
  end

  test "a crashing job is reported" do
    stub_pending_accounts(@instance, accounts: [ admin_account_payload(id: 9901) ])

    with_broken_mapper do
      assert_raises(TypeError) { SyncInstanceJob.perform_now(@instance) }
    end

    assert_equal 1, sentry_events.size
    assert_equal "TypeError", last_sentry_event.exception.values.last.type
  end

  test "a revoked token is expected, not reported" do
    stub_request(:get, "#{@instance.base_url}/api/v2/admin/accounts")
      .with(query: hash_including({ "status" => "pending" }))
      .to_return(status: 401, body: { "error" => "The access token was revoked" }.to_json,
        headers: { "Content-Type" => "application/json" })

    assert_raises(Mastodon::Unauthorized) { SyncInstanceJob.perform_now(@instance) }

    assert_empty sentry_events
  end

  test "failures the app survives are reported through Rails.error" do
    Rails.error.report(RuntimeError.new("checksum mismatch"), handled: true)

    assert_equal 1, sentry_events.size
  end

  test "expected Mastodon failures stay out even when reported explicitly" do
    %w[ConnectionError ServerError RateLimited Unauthorized Forbidden NotFound].each do |name|
      Rails.error.report(Mastodon.const_get(name).new("expected"), handled: true)
    end

    assert_empty sentry_events
  end

  test "requests carry no search terms, cookies or referer" do
    collection = Sentry.configuration.data_collection

    params = collection.url_query_params.filter({ "search" => "alice@example.org", "page" => "2", "applicant_email" => "x" })
    assert_equal({ "search" => "[Filtered]", "page" => "2", "applicant_email" => "[Filtered]" }, params)

    headers = collection.http_headers.request.filter({ "Referer" => "https://w.example/?search=alice", "Accept" => "text/html" })
    assert_equal "[Filtered]", headers["Referer"]
    assert_equal "text/html", headers["Accept"]

    assert_empty collection.cookies.filter({ "_waterhole_session" => "abc" }, cookie: true)
    refute collection.user_info
    refute collection.database_query_data
    assert_empty collection.http_bodies
  end
end
