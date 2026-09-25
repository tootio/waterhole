require "application_system_test_case"

# dropdown_controller.js: the account menu in the header and the email
# template menu on a request share it.
class DropdownTest < ApplicationSystemTestCase
  setup do
    @moderator = moderators(:avery)
    sign_in_as @moderator
  end

  test "the account menu opens, and closes on a click outside" do
    visit root_path
    summary = find("header details summary")
    assert_equal "false", summary["aria-expanded"]
    assert_equal "account-menu", summary["aria-controls"]

    summary.click
    assert_button "Sign out"
    # The toggle event that updates it is async; these wait for it.
    assert_selector "header details summary[aria-expanded=true]"

    find("main h1").click
    assert_no_button "Sign out"
    assert_selector "header details summary[aria-expanded=false]"
  end

  test "Escape closes the account menu and puts focus back on its toggle" do
    visit root_path
    find("header details summary").click
    assert_button "Sign out"

    press :tab
    assert_equal "Sign out", active_element_text
    press :escape

    assert_no_button "Sign out"
    assert page.evaluate_script("document.activeElement === document.querySelector('header details summary')"),
      "focus should return to the toggle"
  end

  test "tabbing out of the account menu closes it" do
    visit root_path
    find("header details summary").click
    press :tab # Sign out
    press :tab # out of the header

    assert_no_button "Sign out"
  end

  # The account menu used to come first in the DOM, while sitting last on screen.
  test "the header tabs in reading order" do
    visit root_path
    page.execute_script("document.activeElement.blur()")

    # The two skip links come first; they sit outside the header.
    names = 7.times.map do
      press :tab
      page.evaluate_script(<<~JS)
        (() => {
          const el = document.activeElement
          if (el.closest("header") === null) return null
          return el.tagName === "SUMMARY" ? "account" : el.textContent.trim().split(/\\s+/)[0]
        })()
      JS
    end.compact

    assert_equal %w[Waterhole Queue My Herds account], names
  end

  test "the email template menu closes on Escape and on a click outside" do
    EmailTemplate.create!(instance: @moderator.instance, name: "Ask for more", body: "Hello {{username}}")
    visit registration_request_path(registration_requests(:pending_alpha))

    summary = find("main details summary", text: "email")
    summary.click
    assert_link "Ask for more"
    assert_selector "main details summary[aria-expanded=true]"

    press :escape
    assert_no_link "Ask for more"
    assert page.evaluate_script("document.activeElement.textContent.includes('email')")

    summary.click
    assert_link "Ask for more"
    find("main h1").click
    assert_no_link "Ask for more"
  end

  private

  def press(*keys) = page.driver.browser.action.send_keys(*keys).perform

  def active_element_text = page.evaluate_script("document.activeElement.textContent.trim()")
end
