require "application_system_test_case"

# The <select multiple>s tom_select_controller.js enhances: the queue's flag
# and watchword filters, and a watchword's fields.
class FilterSelectsTest < ApplicationSystemTestCase
  setup do
    @moderator = moderators(:avery)
    @rowan = registration_requests(:pending_alpha) # "…a smaller server…"
    @smaller = KeywordRule.create!(instance: @moderator.instance, pattern: "smaller", match_type: "word", severity: "info")
    KeywordRule.create!(instance: @moderator.instance, pattern: "casino", match_type: "word", severity: "info")
    @rowan.recompute_flags!
    sign_in_as @moderator
  end

  test "choosing a watchword filters the queue, and the chip stays" do
    visit registration_requests_path
    assert_selector "#registration_request_#{registration_requests(:claimed_alpha).id}"

    open_select "Watchword"
    find(".ts-dropdown .option", text: "smaller").click

    assert_current_path(/watchword/)
    assert_selector "#registration_request_#{@rowan.id}"
    assert_no_selector "#registration_request_#{registration_requests(:claimed_alpha).id}"
    within(watchword_select) { assert_selector ".item", text: "smaller" }

    watchword_select.find(".item", text: "smaller").find(".remove").click
    assert_selector "#registration_request_#{registration_requests(:claimed_alpha).id}"
    assert_selector ".ts-wrapper", count: 3
  end

  test "status chips: several at once, and none for any status" do
    rejected = registration_requests(:rejected_alpha)
    visit registration_requests_path
    assert_no_selector "#registration_request_#{rejected.id}"

    open_select "Status"
    find(".ts-dropdown .option", text: "Rejected", exact_text: true).click
    assert_selector "#registration_request_#{rejected.id}"
    assert_selector "#registration_request_#{@rowan.id}"

    %w[Pending Rejected].each { |label| status_select.find(".item", text: label).find(".remove").click }
    select "Either", from: "Email"
    assert_selector "#registration_request_#{registration_requests(:jules_alpha).id}"
    assert_selector "#registration_request_#{rejected.id}"
  end

  test "two flags, all of them, at a severity" do
    claimed = registration_requests(:claimed_alpha)
    [ @rowan, claimed ].each { it.flags.create!(rule: "shared_ip", severity: "warning") }
    claimed.flags.create!(rule: "tor_relay", severity: "warning")
    visit registration_requests_path

    open_select "Flag"
    # The list stays open, ticking what is chosen.
    [ "Shared IP", "Tor relay" ].each { |label| find(".ts-dropdown .option", text: label).click }
    assert_selector ".ts-dropdown .option input:checked", count: 2
    assert_selector "#registration_request_#{@rowan.id}"

    find("label", text: "all of", match: :first).click
    assert_no_selector "#registration_request_#{@rowan.id}"
    assert_selector "#registration_request_#{claimed.id}"

    select "Critical and above", from: "Severity"
    assert_no_selector "#registration_request_#{claimed.id}"
    assert_current_path(/severity=critical/)
    within(flag_select) { assert_selector ".item", count: 2 }
  end

  test "a watchword saves the fields chosen for it" do
    visit edit_keyword_rule_path(@smaller)

    [ "Join reason", "Profile note", "Display name" ].each do |label|
      find(".ts-control .item", text: label).find(".remove").click
    end
    click_on "Update Keyword rule"

    assert_text "Rule updated."
    assert_equal %w[username], @smaller.reload.fields
  end

  private

  # The label opens the list and focuses its search field, as it would for a
  # person -- clicking the control's middle could land on a chip instead.
  def open_select(label) = find("label", text: label, exact_text: true).click

  def status_select = find("select[name='status[]']", visible: :all).sibling(".ts-wrapper")

  def flag_select = find("select[name='flag[]']", visible: :all).sibling(".ts-wrapper")

  def watchword_select = find("select[name='watchword[]']", visible: :all).sibling(".ts-wrapper")
end
