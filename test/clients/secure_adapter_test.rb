require "test_helper"

class SecureAdapterTest < ActiveSupport::TestCase
  URL = "https://mastodon.example/api/v1/instance".freeze

  setup { stub_request(:get, URL).to_return(status: 200, body: "{}") }

  # SsrfGuard.pin! is a no-op outside production, so swap in a recorder to see
  # whether Faraday actually hands it the Net::HTTP instance.
  def pinned_addresses
    pinned = []
    original = SsrfGuard.method(:pin!)
    SsrfGuard.define_singleton_method(:pin!) { |http| pinned << http.address }
    yield
    pinned
  ensure
    SsrfGuard.define_singleton_method(:pin!, original)
  end

  test "pins every connection built through it" do
    connection = Faraday.new { |f| SecureAdapter.use(f) }

    assert_equal [ "mastodon.example" ], pinned_addresses { connection.get(URL) }
  end

  test "a blocked host aborts the request" do
    connection = Faraday.new { |f| SecureAdapter.use(f) }
    original = SsrfGuard.method(:pin!)
    SsrfGuard.define_singleton_method(:pin!) { |_http| raise SsrfGuard::BlockedHost }

    assert_raises(SsrfGuard::BlockedHost) { connection.get(URL) }
  ensure
    SsrfGuard.define_singleton_method(:pin!, original)
  end

  test "every outbound client routes through it" do
    connections = {
      "Mastodon::Client" => Mastodon::Client.new(base_url: "https://mastodon.example", access_token: nil).send(:connection),
      "SyncIftasDniBlocklistJob" => SyncIftasDniBlocklistJob.new.send(:http),
      "RefreshIpDatabasesJob" => RefreshIpDatabasesJob.new.send(:http)
    }

    connections.each do |name, connection|
      assert_equal [ "mastodon.example" ], pinned_addresses { connection.get(URL) }, "#{name} does not pin its connections"
    end
  end
end
