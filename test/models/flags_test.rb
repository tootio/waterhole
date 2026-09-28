require "test_helper"

class FlagsTest < ActiveSupport::TestCase
  setup { @request = registration_requests(:pending_alpha) }

  def flag_rules_for(request) = request.reload.flags.pluck(:rule)

  test "a blank reason is flagged" do
    @request.update!(invite_request: nil)
    @request.recompute_flags!

    assert_includes flag_rules_for(@request), "no_invite_request"
  end

  test "a very short reason is flagged, but a real one is not" do
    @request.update!(invite_request: "let me in")
    @request.recompute_flags!
    assert_includes flag_rules_for(@request), "short_invite_request"

    @request.update!(invite_request: "I have been part of this community for years and would like to join properly.")
    @request.recompute_flags!
    assert_not_includes flag_rules_for(@request), "short_invite_request"
  end

  test "a disposable email domain is flagged" do
    @request.update!(email: "throwaway@mailinator.com")
    @request.recompute_flags!

    assert_includes flag_rules_for(@request), "disposable_email"
    assert_equal "mailinator.com", @request.flags.find_by(rule: "disposable_email").details["domain"]
  end

  test "a subdomain of a disposable email domain is flagged, but not a lookalike" do
    @request.update!(email: "throwaway@anything.mailinator.com")
    @request.recompute_flags!

    flag = @request.reload.flags.find_by(rule: "disposable_email")
    assert flag
    assert_equal "anything.mailinator.com", flag.details["domain"]
    assert_equal "mailinator.com", flag.details["listed"]

    @request.update!(email: "someone@mailinator-fan.org")
    @request.recompute_flags!
    assert_not_includes flag_rules_for(@request), "disposable_email"
  end

  test "a shared signup IP is flagged on both requests" do
    other = registration_requests(:claimed_alpha)
    @request.update!(ip: "192.0.2.50")
    other.update!(ip: "192.0.2.50")

    @request.recompute_flags!

    flag = @request.reload.flags.find_by(rule: "shared_ip")
    assert flag
    assert_includes flag.details["usernames"], other.username
  end

  test "a reapplication after a rejection is flagged, which Mastodon itself cannot see" do
    # Mastodon deletes the account on rejection, so only our mirror remembers.
    rejected = registration_requests(:rejected_alpha)
    @request.update!(email: rejected.email)
    @request.recompute_flags!

    flag = @request.reload.flags.find_by(rule: "reapplication")
    assert flag
    assert_equal "email", flag.details["matched_on"]
    assert_equal "critical", flag.severity
  end

  test "a reapplication from the same network is a warning, and says so" do
    rejected = registration_requests(:rejected_alpha)
    @request.update!(email: "someone-new@example.org", ip: rejected.ip)
    @request.recompute_flags!

    flag = @request.reload.flags.find_by(rule: "reapplication")
    assert flag
    assert_equal "ip", flag.details["matched_on"], "the email did not match, so the label must not say it did"
    assert_equal "warning", flag.severity
  end

  test "a rejection from a relay address is no evidence against the network" do
    rejected = registration_requests(:rejected_alpha)
    rejected.update!(ip_relay: "tor")
    @request.update!(email: "someone-new@example.org", ip: rejected.ip)
    @request.recompute_flags!

    assert_not_includes flag_rules_for(@request), "reapplication"
  end

  # Its verdict was reached on these flags; the world moving on (a list
  # refresh, a watchword edit) belongs to the pending queue.
  test "a decided request re-runs only the cross-instance rules" do
    rejected = registration_requests(:rejected_alpha)
    rejected.update_columns(email_domain: "mailinator.com")
    KeywordRule.create!(instance: rejected.instance, pattern: "let me in", match_type: "substring", severity: "warning")
    rejected.recompute_flags!

    assert_empty flag_rules_for(rejected) & %w[disposable_email keyword_hit short_invite_request]
  end

  test "a request without an email does not match rejected requests without one" do
    rejected = registration_requests(:rejected_alpha)
    rejected.update_columns(canonical_email_hash: nil, ip: "198.51.100.1")
    @request.update_columns(canonical_email_hash: nil)
    @request.recompute_flags!

    assert_not_includes flag_rules_for(@request), "reapplication"
  end

  test "relay addresses are shared by strangers, so they are not a shared IP" do
    other = registration_requests(:claimed_alpha)
    @request.update!(ip: "192.0.2.50", ip_relay: "private_relay")
    other.update!(ip: "192.0.2.50", ip_relay: "private_relay")
    [ @request, other ].each(&:recompute_flags!)

    assert_not_includes flag_rules_for(@request), "shared_ip"
    assert_not_includes flag_rules_for(other), "shared_ip"
  end

  test "a watchword hit takes the rule's severity" do
    KeywordRule.create!(instance: @request.instance, pattern: "airdrop", match_type: "word", severity: "critical")
    @request.update!(invite_request: "join my airdrop for guaranteed returns")
    @request.recompute_flags!

    flag = @request.reload.flags.find_by(rule: "keyword_hit")
    assert flag
    assert_equal "critical", flag.severity
    assert_includes flag.details["patterns"], "airdrop"
  end

  test "a runaway regex cannot hang the queue" do
    rule = KeywordRule.create!(instance: @request.instance, pattern: "(a+)+$", match_type: "regex", severity: "warning")

    assert_nothing_raised do
      Timeout.timeout(5) { rule.matches?("#{"a" * 60}!") }
    end
  end

  test "an invalid regex is rejected at save time rather than at sync time" do
    rule = KeywordRule.new(instance: @request.instance, pattern: "([unclosed", match_type: "regex", severity: "warning")

    refute rule.valid?
    assert_match(/valid regular expression/, rule.errors.full_messages.to_sentence)
  end

  test "recompute is idempotent and removes flags that no longer apply" do
    @request.update!(invite_request: nil)
    @request.recompute_flags!
    assert_includes flag_rules_for(@request), "no_invite_request"

    3.times { @request.recompute_flags! }
    assert_equal 1, @request.reload.flags.where(rule: "no_invite_request").count

    @request.update!(invite_request: "A perfectly good and sufficiently long explanation of my interest.")
    @request.recompute_flags!
    assert_not_includes flag_rules_for(@request), "no_invite_request"
  end

  test "counter cache and max severity track the flags" do
    KeywordRule.create!(instance: @request.instance, pattern: "airdrop", match_type: "word", severity: "critical")
    @request.update!(invite_request: "airdrop", email: "x@mailinator.com")
    @request.recompute_flags!

    @request.reload
    assert_equal @request.flags.count, @request.flags_count
    assert_equal "critical", Flag.severities.key(@request.max_flag_severity)
  end

  test "every rule has a label for people to read" do
    Flags.rule_names.each do |rule|
      assert I18n.exists?("flags.#{rule}.label", :en), "missing flags.#{rule}.label in config/locales/en.yml"
    end
    assert_equal "IP active elsewhere", Flag.label_for("ip_active_elsewhere")
    assert_equal "Datacenter ASN", Flag.label_for("datacenter_asn")
  end
end
