require "test_helper"

class Ip::TorRelaysTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  ONIONOO = {
    "relays" => [
      { "or_addresses" => [ "203.0.113.10:9001", "[2001:db8::10]:9001" ] },
      # An exit whose traffic leaves from a different address than it listens on.
      { "or_addresses" => [ "203.0.113.20:443" ], "exit_addresses" => [ "203.0.113.99" ] },
      { "or_addresses" => nil }
    ]
  }.freeze

  def onionoo_with(count)
    { "relays" => (0...count).map { { "or_addresses" => [ "10.#{it / 128}.#{(it % 128) * 2}.1:9001" ] } } }.to_json
  end

  test "reads listening and exit addresses, IPv4 and IPv6" do
    Dir.mktmpdir do |dir|
      file = File.join(dir, "onionoo.json")
      File.write(file, ONIONOO.to_json)

      assert_equal %w[203.0.113.10 2001:db8::10 203.0.113.20 203.0.113.99], Ip::TorRelays.parse(file)
    end
  end

  test "the hourly job installs the list, and enrichment and the flag use it" do
    Dir.mktmpdir do |dir|
      Ip::Databases.stub_directory(dir) do
        stub_request(:get, Ip::TorRelays::SOURCE_URL).to_return(status: 200, body: onionoo_with(Ip::TorRelays::MINIMUM_RANGES))
        RefreshTorRelaysJob.perform_now

        assert Ip::TorRelays.include?("10.0.2.1")
        refute Ip::TorRelays.include?("10.0.1.1")

        request = registration_requests(:pending_alpha)
        request.update!(ip: "10.0.2.1", ip_enriched_at: nil)
        RegistrationRequests::Enrichment.apply(request)
        request.save!
        request.recompute_flags!

        assert request.reload.ip_relay_tor?
        flag = request.flags.find_by(rule: "tor_relay")
        assert_equal "info", flag.severity
      end
    end
  end

  test "an answer that is not the relay list keeps the previous one" do
    Dir.mktmpdir do |dir|
      Ip::Databases.stub_directory(dir) do
        stub_request(:get, Ip::TorRelays::SOURCE_URL).to_return(status: 200, body: onionoo_with(Ip::TorRelays::MINIMUM_RANGES))
        RefreshTorRelaysJob.perform_now
        before = Ip::TorRelays.path.read

        stub_request(:get, Ip::TorRelays::SOURCE_URL).to_return(status: 200, body: onionoo_with(2))
        RefreshTorRelaysJob.perform_now

        assert_equal before, Ip::TorRelays.path.read
      end
    end
  end

  test "an ordinary address raises no Tor flag" do
    request = registration_requests(:pending_alpha)
    request.update!(ip_relay: nil)
    request.recompute_flags!

    assert_nil request.reload.flags.find_by(rule: "tor_relay")
  end
end
