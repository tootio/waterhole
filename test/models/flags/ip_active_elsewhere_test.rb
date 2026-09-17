require "test_helper"

class Flags::IpActiveElsewhereTest < ActiveSupport::TestCase
  def request_on(instance, id, ip)
    instance.registration_requests.create!(mastodon_account_id: id, username: "u#{id}",
      signed_up_at: 1.hour.ago, ip:, invite_request: "A sufficiently long reason to join.")
  end

  def flag_for(request) = request.reload.flags.find_by(rule: "ip_active_elsewhere")

  test "the same IPv4 address on two participating instances flags both" do
    a = request_on(instances(:alpha), "9001", "192.0.2.77")
    b = request_on(instances(:beta), "9002", "192.0.2.77")
    [ a, b ].each(&:recompute_flags!)

    assert flag_for(a)
    assert flag_for(b)
    assert_equal "exact", flag_for(a).details["scope"]
  end

  test "IPv4 matches exactly, so a neighbouring address does not" do
    a = request_on(instances(:alpha), "9003", "192.0.2.77")
    request_on(instances(:beta), "9004", "192.0.2.78")
    a.recompute_flags!

    refute flag_for(a), "unrelated customers routinely sit next to each other"
  end

  # IPv6 hosts rotate their low bits constantly, so exact matching would miss
  # almost every real repeat signup.
  test "IPv6 matches on the /64" do
    a = request_on(instances(:alpha), "9005", "2001:db8:aa:bb:1111:2222:3333:4444")
    b = request_on(instances(:beta), "9006", "2001:db8:aa:bb:9999:8888:7777:6666")
    [ a, b ].each(&:recompute_flags!)

    assert flag_for(a)
    assert_equal "/64", flag_for(a).details["scope"]
  end

  test "a different IPv6 /64 does not match" do
    a = request_on(instances(:alpha), "9007", "2001:db8:aa:bb::1")
    request_on(instances(:beta), "9008", "2001:db8:aa:cc::1")
    a.recompute_flags!

    refute flag_for(a)
  end

  test "an instance that has not opted in neither sees nor is disclosed" do
    a = request_on(instances(:alpha), "9009", "192.0.2.90")
    g = request_on(instances(:gamma), "9010", "192.0.2.90") # gamma opted out
    [ a, g ].each(&:recompute_flags!)

    refute flag_for(g), "gamma opted out, so it must not see other instances"
    refute flag_for(a), "gamma opted out, so its applicants must not be disclosed either"
  end

  test "only active requests count" do
    a = request_on(instances(:alpha), "9011", "192.0.2.91")
    b = request_on(instances(:beta), "9012", "192.0.2.91")
    b.update!(status: "rejected", resolved_at: Time.current)
    a.recompute_flags!

    refute flag_for(a)
  end

  test "an instance past its terms grace stops participating" do
    a = request_on(instances(:alpha), "9013", "192.0.2.92")
    request_on(instances(:beta), "9014", "192.0.2.92")
    instances(:beta).update!(status: "terms_outdated", terms_grace_until: 1.hour.ago)
    a.recompute_flags!

    refute flag_for(a), "a locked-out instance must not keep feeding signals"
  end

  test "counterparts drives the reverse recompute" do
    a = request_on(instances(:alpha), "9015", "192.0.2.93")
    b = request_on(instances(:beta), "9016", "192.0.2.93")

    assert_equal [ b.id ], Flags::IpActiveElsewhere.counterparts(a).map(&:id)
  end

  # A shared /64 behind carrier-grade NAT could otherwise match hundreds of rows
  # and fan out a job per match.
  test "counterparts are capped" do
    a = request_on(instances(:alpha), "9017", "2001:db8:ca9:1::1")
    30.times { |i| request_on(instances(:beta), "95#{i}", "2001:db8:ca9:1::#{i + 2}") }
    a.recompute_flags!

    assert_equal Flags::IpActiveElsewhere::COUNTERPART_CAP, flag_for(a).details["count"]
    assert flag_for(a).details["capped"]
  end

  test "clearing the address clears the generated match key" do
    a = request_on(instances(:alpha), "9018", "192.0.2.94")
    assert a.reload.ip_group.present?

    a.update_columns(ip: nil)

    assert_nil a.reload.ip_group,
      "a derived key outliving its address would keep matching people"
  end
end
