ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

# Tests must never reach a real Mastodon server or a real resolver.
WebMock.disable_net_connect!(allow_localhost: true)

Dir[Rails.root.join("test/support/**/*.rb")].each { |f| require f }

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    fixtures :all

    include MastodonStubs
    include LegalStubs
    include IpStubs

    setup do
      # DnsAllowlist reads WATERHOLE_FAKE_DNS at call time; keep tests hermetic.
      ENV.delete("WATERHOLE_FAKE_DNS")
      ENV.delete("WATERHOLE_POLICY_MODE")

      # Default to a deployment with no legal documents, so the suite asserts the
      # same thing whether or not the developer running it has installed their
      # own. Tests that need the terms gate use `with_legal_documents`.
      LegalDocuments.directory = Rails.root.join("test/fixtures/files/legal_empty")

      # Same reasoning for the 18 MB IP databases: tests that want them use
      # `with_ip_databases` and the committed fixture files.
      Ip::Databases.directory = Rails.root.join("test/fixtures/files/ipdata_empty")

      # Rate-limit counters are per process; start every test with none spent.
      # NOT Rails.cache: that is the null store, and the limiter counts in
      # config.action_controller.cache_store (see config/environments/test.rb).
      ActionController::Base.cache_store.clear
    end

    teardown do
      LegalDocuments.directory = nil
      Ip::Databases.directory = nil
    end
  end
end

class ActionDispatch::IntegrationTest
  # Stubs the search Instances::ProveIdentity asks for, answering it as Mastodon
  # does: by fetching the challenge URL, signed with `key`, before it replies.
  # The fetch comes from a separate session, as it would from the server.
  def stub_mastodon_resolve(domain, key: actor_key)
    stub_request(:get, "https://#{domain}/api/v2/search").with(query: hash_including("resolve" => "true"))
      .to_return do |request|
        url = Rack::Utils.parse_query(URI(request.uri.to_s).query)["q"]
        open_session { it.get URI(url).path, headers: mastodon_signed_headers(url, key:, key_id: "https://#{domain}/actor#main-key") }
        { status: 200, body: { "accounts" => [], "statuses" => [], "hashtags" => [] }.to_json,
          headers: { "Content-Type" => "application/json" } }
      end
  end

  # Signs in through the real endpoint rather than forging a cookie, so these
  # tests exercise the same session machinery the app uses. (Rails.env.local? is
  # true in test, so the development sign-in route is available here.)
  # remember: ticks "Remember this instance in this browser".
  def sign_in_as(moderator, remember: false)
    token = Rails.application.message_verifier(:dev_sign_in)
      .generate({ moderator_id: moderator.id }, expires_in: 1.hour)
    get "/dev/sign_in", params: { token:, remember: remember ? "1" : "0" }
    moderator
  end
end
