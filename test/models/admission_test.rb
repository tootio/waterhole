require "test_helper"

class AdmissionTest < ActiveSupport::TestCase
  test "an unlisted domain that published the record is admitted" do
    assert Admission.call("newcomer.example", resolver: dns_ok).admitted?
  end

  test "a blocked domain is refused" do
    result = Admission.call("spam.example", resolver: dns_ok)

    assert_equal :blocked_by_policy, result.outcome
    assert result.policy_refusal?
    assert_includes result.message, "farm accounts"
  end

  test "blocking covers subdomains when the policy says so" do
    assert_equal :blocked_by_policy, Admission.call("node.badnet.example", resolver: dns_ok).outcome
    # ...but an unrelated domain that merely ends similarly is untouched.
    assert Admission.call("notbadnet.example", resolver: dns_ok).admitted?
  end

  test "deny beats allow" do
    # A blocklist an allowlist entry could override would not be a blocklist.
    DomainPolicy.create!(domain: "spam.example", kind: "allowed") rescue nil
    DomainPolicy.find_by(domain: "spam.example").update!(kind: "blocked", reason: "still blocked")

    assert_equal :blocked_by_policy, Admission.call("spam.example", resolver: dns_ok).outcome
  end

  test "a blocked domain triggers no DNS lookup at all" do
    # The cheap local check runs first precisely so a domain we refuse to serve
    # never causes an outbound request on its behalf.
    exploding = Class.new { def txt_records(_) = raise("DNS must not be consulted") }.new

    assert_equal :blocked_by_policy, Admission.call("spam.example", resolver: exploding).outcome
  end

  test "allowlist_only refuses anything not explicitly allowed" do
    ENV["WATERHOLE_POLICY_MODE"] = "allowlist_only"

    assert Admission.call("alpha.example", resolver: dns_ok).admitted?, "alpha is on the allowlist"

    result = Admission.call("newcomer.example", resolver: dns_ok)
    assert_equal :not_on_allowlist, result.outcome
    assert result.policy_refusal?
  ensure
    ENV.delete("WATERHOLE_POLICY_MODE")
  end

  test "passing policy but missing the DNS record is refused, and is the admin's to fix" do
    result = Admission.call("newcomer.example", resolver: dns_records([]))

    assert_equal :dns_not_allowlisted, result.outcome
    assert result.fixable_by_admin?
    refute result.policy_refusal?
  end

  test "an unreachable resolver is reported as our problem, not theirs" do
    result = Admission.call("newcomer.example", resolver: dns_unreachable)

    assert_equal :dns_unreachable, result.outcome
    assert_includes result.message, "our side"
  end
end
