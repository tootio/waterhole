require "application_system_test_case"

# The queue page's bulk claim/release/approve/reject (bulk_select_controller.js):
# one JSON request per selected row, results collected in a dialog.
class BulkActionsTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @moderator = moderators(:avery)
    @instance = instances(:alpha)
    @rowan = registration_requests(:pending_alpha)
    @jules = registration_requests(:jules_alpha)
    @claimed = registration_requests(:claimed_alpha) # held by Blake
    sign_in_as @moderator
  end

  test "rejecting two selected requests reports both in the dialog" do
    stub_decision(@instance, id: @rowan.mastodon_account_id, action: "reject")
    stub_decision(@instance, id: @jules.mastodon_account_id, action: "reject")

    visit registration_requests_path
    select_rows @rowan, @jules
    assert_text "2 selected"

    click_on "Reject"
    within("#confirm-message") { assert_text "Reject 2 requests?" }
    click_on "Confirm"

    within "#bulk-dialog" do
      assert_text "Done: 2 rejected."
      assert_result @rowan, "Rejected"
      assert_result @jules, "Rejected"
    end
    assert_equal "rejected", @rowan.reload.status
    assert_equal "rejected", @jules.reload.status
  end

  test "the confirmation warns about requests claimed by someone else" do
    visit registration_requests_path
    select_rows @rowan, @claimed

    click_on "Approve"

    within("#confirm-message") { assert_text "1 of them is claimed by another moderator." }
    click_on "Cancel"
    assert_no_selector "#bulk-dialog[open]"
  end

  test "a 429 queues that request and pauses the run before the next one" do
    stub_decision_rate_limited(@instance, id: @rowan.mastodon_account_id, action: "reject", reset_at: 2.seconds.from_now)
    stub_decision(@instance, id: @jules.mastodon_account_id, action: "reject")

    visit registration_requests_path
    select_rows @rowan, @jules
    click_on "Reject"
    click_on "Confirm"

    within "#bulk-dialog" do
      assert_text "Paused for Mastodon's rate limit"
      assert_text "Done:", wait: 10
      assert_result @rowan, "Queued"
      assert_result @jules, "Rejected"
    end
  end

  test "bulk claim skips nothing it can take, and bulk release leaves others' claims alone" do
    visit registration_requests_path
    select_rows @rowan, @claimed

    click_on "Claim"
    within "#bulk-dialog" do
      assert_result @rowan, "Claimed"
      assert_result @claimed, "Taken"
      click_on "Close"
    end
    assert_equal @moderator, @rowan.reload.claimed_by

    # The refresh broadcast is not delivered here (no job runs), so reload to
    # pick up the new claim state; the selection starts over with the page.
    visit registration_requests_path
    select_rows @rowan, @claimed
    click_on "Release"
    within "#bulk-dialog" do
      assert_result @rowan, "Released"
      assert_result @claimed, "Skipped"
    end
    assert_nil @rowan.reload.claimed_by
    assert_equal moderators(:blake), @claimed.reload.claimed_by
  end

  test "x selects the focused row" do
    visit registration_requests_path
    assert_text "@#{@rowan.username}"

    find_by_id(ActionView::RecordIdentifier.dom_id(@rowan, :link)).send_keys("x")

    assert checkbox_for(@rowan).checked?
    assert_text "1 selected"
  end

  private

    def checkbox_for(request) = find("input[aria-label='Select @#{request.username}']")

    def select_rows(*requests) = requests.each { checkbox_for(it).click }

    def assert_result(request, label)
      assert_selector "li", text: /@#{request.username}\s*#{label}/
    end
end
