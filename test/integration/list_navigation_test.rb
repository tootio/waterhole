require "test_helper"

class ListNavigationTest < ActionDispatch::IntegrationTest
  setup do
    @moderator = moderators(:avery)
    # newest first (the default sort): pending_alpha, claimed_alpha, jules_alpha
    @pending_alpha = registration_requests(:pending_alpha)
    @claimed_alpha = registration_requests(:claimed_alpha)
    @jules_alpha   = registration_requests(:jules_alpha)
    sign_in_as @moderator
  end

  test "the detail page shows previous/next links when the request is in the current list" do
    get registration_request_path(@claimed_alpha)

    assert_select "a", "← Previous"
    assert_select "a", "Next →"
  end

  test "the detail page hides previous/next links when the request isn't in the current filter" do
    rejected = registration_requests(:rejected_alpha)

    get registration_request_path(rejected) # default filter is status: pending

    assert_select "a", { count: 0, text: "← Previous" }
    assert_select "a", { count: 0, text: "Next →" }
  end

  test "next redirects to the next request in the current order" do
    get next_registration_request_path(@pending_alpha)

    assert_redirected_to registration_request_path(@claimed_alpha)
  end

  test "previous redirects to the previous request in the current order" do
    get previous_registration_request_path(@claimed_alpha)

    assert_redirected_to registration_request_path(@pending_alpha)
  end

  test "next carries the active filters and sort along" do
    get next_registration_request_path(@jules_alpha, sort: "oldest")

    assert_redirected_to registration_request_path(@claimed_alpha, sort: "oldest")
  end

  test "next at the end of the list falls back to the queue with a flash" do
    get next_registration_request_path(@jules_alpha)

    assert_redirected_to registration_requests_path
    follow_redirect!
    assert_match(/No more requests/, flash[:notice])
  end

  test "previous at the start of the list falls back to the queue with a flash" do
    get previous_registration_request_path(@pending_alpha)

    assert_redirected_to registration_requests_path
  end

  test "a moderator cannot walk next/previous onto another instance's request" do
    other = registration_requests(:other_instance)

    get next_registration_request_path(other)

    assert_response :not_found
  end

  # Regression: the same open-redirect risk queue_row_path guards against
  # (see "pagination links stay on this site" in queue_test.rb) applies here,
  # since these links are also built from the current request's params.
  test "previous/next links stay on this site and carry only the filters" do
    get registration_request_path(@claimed_alpha, host: "evil.example", protocol: "javascript", sort: "oldest")

    assert_response :success
    assert_select "a", text: "Next →" do |links|
      href = links.first["href"]
      assert href.start_with?("/"), "expected a path, got #{href.inspect}"
      refute_match(/evil|javascript/, href)
      assert_match(/sort=oldest/, href)
    end
  end
end
