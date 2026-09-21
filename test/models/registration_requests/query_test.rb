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
end
