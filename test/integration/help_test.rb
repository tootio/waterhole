require "test_helper"

class HelpTest < ActionDispatch::IntegrationTest
  setup do
    @moderator = moderators(:avery)
    sign_in_as @moderator
  end

  test "the shortcuts page lists the known shortcuts" do
    get keyboard_shortcuts_help_path

    assert_response :success
    assert_select "kbd", text: "j"
    assert_select "kbd", text: "k"
    assert_match(/Approve/, response.body)
    assert_match(/Reject/, response.body)
    assert_match(/Claim/, response.body)
  end

  test "the queue and detail pages link to the shortcuts page" do
    get registration_requests_path
    assert_select "a[href=?]", keyboard_shortcuts_help_path, text: /Keyboard shortcuts/

    get registration_request_path(registration_requests(:pending_alpha))
    assert_select "a[href=?]", keyboard_shortcuts_help_path, text: /Keyboard shortcuts/
  end

  test "a flag's help page shows the rule's general explanation and this flag's own details" do
    request = registration_requests(:pending_alpha)
    flag = request.flags.create!(rule: "disposable_email", severity: "warning", details: { "domain" => "mailinator.com" })

    get flag_help_path(flag)

    assert_response :success
    assert_match(/throwaway/, response.body) # the general help text for disposable_email
    assert_match(/mailinator\.com/, response.body) # this flag's own detail
    assert_select "dt", "Severity"
    assert_select "dd", text: /Warning/
    assert_select "a[href=?]", registration_request_path(request)
  end

  test "a flag with no details omits the per-request details entry" do
    request = registration_requests(:pending_alpha)
    flag = request.flags.create!(rule: "no_invite_request", severity: "info", details: {})

    get flag_help_path(flag)

    assert_response :success
    assert_select "dt", { count: 0, text: "On this request" }
  end

  test "the flags panel links each flag to its help page, to be opened in the modal" do
    request = registration_requests(:pending_alpha)
    flag = request.flags.create!(rule: "disposable_email", severity: "warning", details: { "domain" => "mailinator.com" })

    get registration_request_path(request)

    assert_select "a[href=?][data-action=?]", flag_help_path(flag), "modal#open"
  end

  test "the shortcuts link is also opened in the modal" do
    get registration_requests_path
    assert_select "a[href=?][data-action=?]", keyboard_shortcuts_help_path, "modal#open"
  end

  test "a moderator cannot view another instance's flag" do
    other = registration_requests(:other_instance)
    flag = other.flags.create!(rule: "disposable_email", severity: "warning", details: { "domain" => "mailinator.com" })

    get flag_help_path(flag)

    assert_response :not_found
  end

  test "an XHR request for a help page renders without the surrounding layout" do
    request = registration_requests(:pending_alpha)
    flag = request.flags.create!(rule: "disposable_email", severity: "warning", details: { "domain" => "mailinator.com" })

    get flag_help_path(flag), headers: { "X-Requested-With" => "XMLHttpRequest" }

    assert_response :success
    assert_select "header", count: 0
    assert_select "nav", count: 0
    assert_select "a", { count: 0, text: "← Back to request" }
    assert_select "h1", flag.label
  end

  test "the queue and detail pages, and the request page's flags, render the shared modal dialog" do
    request = registration_requests(:pending_alpha)
    request.flags.create!(rule: "disposable_email", severity: "warning", details: { "domain" => "mailinator.com" })

    get registration_requests_path
    assert_select "dialog[data-modal-target=?]", "dialog"

    get registration_request_path(request)
    assert_select "dialog[data-modal-target=?]", "dialog"
  end

  test "the regexp help page explains the syntax and the case tips" do
    get regexp_help_path

    assert_response :success
    assert_select "h1", "Regexp help"
    assert_select "code", "(?i)"
    assert_select "code", "(?-i)"
  end

  test "the watchword form links the regexp help, to be opened in the modal" do
    [ new_keyword_rule_path, edit_keyword_rule_path(KeywordRule.create!(instance: instances(:alpha), pattern: "seo")) ].each do |path|
      get path
      assert_select "a[href=?][data-action=?]", regexp_help_path, "modal#open"
    end
  end
end
