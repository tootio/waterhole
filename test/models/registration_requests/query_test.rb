require "test_helper"

class RegistrationRequests::QueryTest < ActiveSupport::TestCase
  def query(filters = {}) = RegistrationRequests::Query.new(RegistrationRequest.none, filters)

  test "the bare queue landing page is unfiltered" do
    assert query.unfiltered?
  end

  test "sort alone doesn't count as a filter" do
    assert query(sort: "risk").unfiltered?
    assert query(sort: "oldest").unfiltered?
  end

  test "a status, claim, email or search filter makes it filtered" do
    refute query(status: "all").unfiltered?
    refute query(claim: "unclaimed").unfiltered?
    refute query(email: "any").unfiltered?
    refute query(search: "spam").unfiltered?
  end

  test "filters by watchword, of the queue's own instance only" do
    rowan = registration_requests(:pending_alpha)
    own   = KeywordRule.create!(instance: instances(:alpha), pattern: "smaller", match_type: "word", severity: "info")
    other = KeywordRule.create!(instance: instances(:beta), pattern: "smaller", match_type: "word", severity: "info")
    rowan.recompute_flags!
    scope = instances(:alpha).registration_requests

    assert_equal [ rowan ], RegistrationRequests::Query.new(scope, { watchword: [ "", own.id.to_s ], status: "all" }).call.to_a
    assert_empty RegistrationRequests::Query.new(scope, { watchword: [ other.id.to_s ], status: "all" }).call
  end

  test "a multiple select's blank entry alone is no filter" do
    assert query(watchword: [ "" ]).unfiltered?
  end

  # Flags from before rule_ids were recorded still name the pattern.
  test "an older flag without rule ids is found by its pattern" do
    rowan = registration_requests(:pending_alpha)
    rule  = KeywordRule.create!(instance: instances(:alpha), pattern: "smaller", match_type: "word", severity: "info")
    rowan.flags.create!(rule: "keyword_hit", severity: "info", details: { "patterns" => [ "smaller" ] })

    assert_equal [ rowan ], RegistrationRequest.with_watchwords([ rule ]).to_a
  end

  test "several watchwords match any of them, or all of them when asked" do
    rowan = registration_requests(:pending_alpha) # "…a smaller server…stronger local community."
    smaller   = KeywordRule.create!(instance: instances(:alpha), pattern: "smaller", match_type: "word", severity: "info")
    community = KeywordRule.create!(instance: instances(:alpha), pattern: "community", match_type: "word", severity: "info")
    casino    = KeywordRule.create!(instance: instances(:alpha), pattern: "casino", match_type: "word", severity: "info")
    rowan.recompute_flags!
    scope = instances(:alpha).registration_requests
    run = ->(ids, match) { RegistrationRequests::Query.new(scope, { watchword: ids.map(&:to_s), watchword_match: match, status: "all" }).call.to_a }

    assert_equal [ rowan ], run.([ smaller.id, casino.id ], "any")
    assert_empty run.([ smaller.id, casino.id ], "all")
    assert_equal [ rowan ], run.([ smaller.id, community.id ], "all")
    assert_empty run.([ smaller.id, 0 ], "all"), "a watchword that no longer exists flagged nothing"
  end

  test "the any-of/all-of switch alone is no filter" do
    assert query(watchword_match: "all").unfiltered?
    assert query(watchword: [ "" ], watchword_match: "any").unfiltered?
  end

  test "a severity applies to the chosen flags themselves" do
    rowan, claimed, jules = registration_requests(:pending_alpha), registration_requests(:claimed_alpha), registration_requests(:jules_alpha)
    rowan.flags.create!(rule: "keyword_hit", severity: "info")
    rowan.flags.create!(rule: "tor_relay", severity: "warning")
    claimed.flags.create!(rule: "keyword_hit", severity: "warning")
    claimed.flags.create!(rule: "shared_ip", severity: "warning")
    scope = instances(:alpha).registration_requests.where(id: [ rowan, claimed, jules ])
    run = ->(filters) { RegistrationRequests::Query.new(scope, filters.merge(status: "all", email: "any")).call.to_set }

    # A warning Tor flag must not let rowan's info watchword match through.
    assert_equal Set[claimed], run.(flag: %w[keyword_hit], severity: "warning")
    assert_equal Set[rowan, claimed], run.(flag: %w[keyword_hit], severity: "info")
    assert_equal Set[claimed], run.(flag: %w[keyword_hit shared_ip], flag_match: "all", severity: "warning")
    assert_equal Set[claimed], run.(flag: %w[keyword_hit shared_ip], severity: "warning")
    assert_equal Set[rowan, claimed], run.(flag: %w[keyword_hit tor_relay], severity: "warning")
    assert_empty run.(flag: %w[keyword_hit no_such_flag], flag_match: "all")
  end

  test "a severity without flags means any flag at it, and info and above means flagged at all" do
    rowan, jules = registration_requests(:pending_alpha), registration_requests(:jules_alpha)
    rowan.flags.create!(rule: "tor_relay", severity: "info")
    scope = instances(:alpha).registration_requests.where(id: [ rowan, jules ])
    run = ->(severity) { RegistrationRequests::Query.new(scope, { severity:, status: "all", email: "any" }).call.to_set }

    assert_equal Set[rowan], run.("info")
    assert_empty run.("warning")
    assert_equal Set[rowan, jules], run.("bogus")
  end

  test "a single flag from an older link still filters" do
    assert_equal [ "shared_ip" ], query(flag: "shared_ip").filters[:flag]
    assert query(flag: [ "" ], flag_match: "all").unfiltered?
  end

  test "statuses are any of the chosen, and an emptied select is any status" do
    rowan, rejected = registration_requests(:pending_alpha), registration_requests(:rejected_alpha)
    scope = instances(:alpha).registration_requests.where(id: [ rowan, rejected ])
    run = ->(status) { RegistrationRequests::Query.new(scope, { status:, email: "any" }).call.to_set }

    assert_equal Set[rowan], run.("pending"), "a single status from an older link"
    assert_equal Set[rowan, rejected], run.([ "", "pending", "rejected" ])
    assert_equal Set[rejected], run.([ "", "rejected" ])
    assert_equal Set[rowan, rejected], run.([ "" ]), "every chip removed"
    assert_equal Set[rowan, rejected], run.("all")
    assert_equal Set[rowan], run.([ "bogus" ]), "nothing valid: the default"
  end

  test "pending alone, however it is sent, is the unfiltered landing page" do
    assert query(status: [ "", "pending" ]).unfiltered?
    assert query(status: "pending").unfiltered?
    refute query(status: [ "" ]).unfiltered?
  end
end
