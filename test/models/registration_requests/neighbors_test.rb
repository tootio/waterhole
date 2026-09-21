require "test_helper"

class RegistrationRequests::NeighborsTest < ActiveSupport::TestCase
  setup do
    @instance = instances(:alpha)
    @pending_alpha = registration_requests(:pending_alpha)  # signed_up_at: 3.hours.ago
    @claimed_alpha = registration_requests(:claimed_alpha)  # signed_up_at: 4.hours.ago
    @jules_alpha   = registration_requests(:jules_alpha)    # signed_up_at: 5.hours.ago
  end

  def neighbors(current, filters = {})
    scope = RegistrationRequests::Query.new(@instance.registration_requests, filters).call
    RegistrationRequests::Neighbors.new(scope, current)
  end

  test "a record within the filtered list reports itself as in the list" do
    assert neighbors(@pending_alpha).in_list?
  end

  test "a record excluded by the current filter is not in the list" do
    refute neighbors(@pending_alpha, search: "nobody-matches-this").in_list?
  end

  test "a record excluded by status is not in the list" do
    rejected = registration_requests(:rejected_alpha)
    refute neighbors(rejected).in_list? # default filter is status: pending
  end

  test "after steps to the next record in newest-first order" do
    # newest first: pending_alpha, claimed_alpha, jules_alpha
    assert_equal @claimed_alpha, RegistrationRequest.find_by(id: neighbors(@pending_alpha).after)
    assert_equal @jules_alpha, RegistrationRequest.find_by(id: neighbors(@claimed_alpha).after)
  end

  test "before steps to the previous record in newest-first order" do
    assert_equal @pending_alpha, RegistrationRequest.find_by(id: neighbors(@claimed_alpha).before)
    assert_equal @claimed_alpha, RegistrationRequest.find_by(id: neighbors(@jules_alpha).before)
  end

  test "after is nil at the end of the list" do
    assert_nil neighbors(@jules_alpha).after
  end

  test "before is nil at the start of the list" do
    assert_nil neighbors(@pending_alpha).before
  end

  test "before/after are nil for a record that isn't in the filtered list" do
    n = neighbors(@pending_alpha, search: "nobody-matches-this")
    assert_nil n.before
    assert_nil n.after
  end

  test "oldest-first order reverses the walk" do
    assert_equal @claimed_alpha, RegistrationRequest.find_by(id: neighbors(@jules_alpha, sort: "oldest").after)
    assert_equal @pending_alpha, RegistrationRequest.find_by(id: neighbors(@claimed_alpha, sort: "oldest").after)
  end

  test "risk sort is honored, not just insertion or signup order" do
    # Direct column update: this test is about Neighbors respecting whatever
    # order riskiest_first produces, not about how severity gets computed.
    @jules_alpha.update_columns(max_flag_severity: Flag.severities[:critical], flags_count: 1)

    # riskiest first: jules_alpha (highest severity) leads, even though it's
    # the OLDEST signup and would be LAST under "newest".
    n = neighbors(@jules_alpha, sort: "risk")
    assert_nil n.before
    assert_equal @claimed_alpha, RegistrationRequest.find_by(id: n.after)
  end

  test "ties on the sort column break deterministically by id, not arbitrarily" do
    same_time = 1.hour.ago
    a = @instance.registration_requests.create!(mastodon_account_id: "9001", username: "tie_a", signed_up_at: same_time, confirmed: true)
    b = @instance.registration_requests.create!(mastodon_account_id: "9002", username: "tie_b", signed_up_at: same_time, confirmed: true)
    lower, higher = [ a, b ].sort_by(&:id)

    assert_equal higher, RegistrationRequest.find_by(id: neighbors(lower).after)
    assert_equal lower, RegistrationRequest.find_by(id: neighbors(higher).before)
  end
end
