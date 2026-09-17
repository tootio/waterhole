require "test_helper"

class Ip::PrivateRelayTest < ActiveSupport::TestCase
  CSV = <<~CSV
    172.224.226.0/27,GB,GB-EN,London,
    172.224.226.32/31,GB,GB-SC,Aberdeen,
    2a02:26f7:b3c0:4000::/64,DE,DE-BE,Berlin,
  CSV

  setup do
    @dir = Pathname(Dir.mktmpdir)
    csv = @dir.join("relay.csv")
    csv.write(CSV)
    @ranges = Ip::RangeList.compile(Ip::PrivateRelay.parse(csv))
  end

  teardown { FileUtils.rm_rf(@dir) }

  def with_installed_list(&)
    Ip::Databases.stub_directory(@dir) do
      Ip::RangeList.write(@ranges, to: Ip::PrivateRelay.path)
      yield
    end
  end

  test "adjacent ranges merge into one" do
    first = IPAddr.new("172.224.226.0").to_i
    last  = IPAddr.new("172.224.226.33").to_i

    assert_equal [ [ first, last ] ], @ranges[4]
    assert_equal 1, @ranges[6].size
  end

  test "finds addresses inside the ranges, and only those" do
    with_installed_list do
      assert Ip::PrivateRelay.include?("172.224.226.5")
      assert Ip::PrivateRelay.include?("172.224.226.33"), "the merged range's last address"
      assert Ip::PrivateRelay.include?("2a02:26f7:b3c0:4000::1")
      assert Ip::PrivateRelay.include?("::ffff:172.224.226.5"), "IPv4-mapped IPv6 is the same host"

      refute Ip::PrivateRelay.include?("172.224.226.34")
      refute Ip::PrivateRelay.include?("172.224.225.255")
      refute Ip::PrivateRelay.include?("2a02:26f7:b3c0:4001::1")
      refute Ip::PrivateRelay.include?("not an address")
    end
  end

  test "without a downloaded list nothing is a relay" do
    Ip::Databases.stub_directory(@dir) do
      refute Ip::PrivateRelay.installed?
      refute Ip::PrivateRelay.include?("172.224.226.5")
    end
  end

  test "enrichment records a relay address" do
    request = registration_requests(:pending_alpha)

    with_installed_list do
      request.ip = "172.224.226.5"
      RegistrationRequests::Enrichment.apply(request)
    end

    assert request.ip_relay_private_relay?
  end
end
