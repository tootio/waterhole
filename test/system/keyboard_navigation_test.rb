require "application_system_test_case"

# Smoke-tests the keyboard navigation and that Turbo works as intended.
class KeyboardNavigationTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  # Longer than Turbo::Debouncer::DEFAULT_DELAY (0.5s), which is how long
  # ClaimsController#broadcast_change's refresh sits debounced before it's
  # actually enqueued.
  REFRESH_DEBOUNCE_MARGIN = 0.7

  setup do
    @moderator = moderators(:avery)
    @pending = registration_requests(:pending_alpha)
    sign_in_as @moderator
  end

  test "claiming and releasing a request with the keyboard on the queue page updates it in place, without reloading the page" do
    visit registration_requests_path(search: @pending.username)
    assert_text "@#{@pending.username}"

    # canary marker that get lost when page reloads
    page.execute_script("window.__systemTestLoaded = true")

    press "j"
    assert page.evaluate_script("document.activeElement.id === #{ActionView::RecordIdentifier.dom_id(@pending, :link).inspect}"),
           "row had no focus after pressing \"j\""

    claim_and_wait_for_refresh_broadcast { press "c" }

    assert_selector "##{ActionView::RecordIdentifier.dom_id(@pending, :link)}[data-claimed-by-me='true']"
    assert_equal @moderator, @pending.reload.claimed_by
    assert page.evaluate_script("window.__systemTestLoaded"),
      "claiming with \"c\" reloaded the page instead of updating the row in place"
    assert page.evaluate_script("document.activeElement.id === #{ActionView::RecordIdentifier.dom_id(@pending, :link).inspect}"),
           "row lost focus after pressing \"c\""

    claim_and_wait_for_refresh_broadcast { press "c" }

    assert_selector "##{ActionView::RecordIdentifier.dom_id(@pending, :link)}[data-claimed-by-me='false']"
    assert_nil @pending.reload.claimed_by
    assert page.evaluate_script("window.__systemTestLoaded"),
      "releasing with \"c\" reloaded the page instead of updating the row in place"
  end

  test "j past the last loaded row loads more and moves into them, without reloading the page" do
    30.times do |i|
      @moderator.instance.registration_requests.create!(mastodon_account_id: "96#{i}",
        username: "paged#{i}", signed_up_at: (i + 1).minutes.ago, confirmed: true)
    end
    ordered = RegistrationRequests::Query.new(@moderator.instance.registration_requests, {}, viewer: @moderator).call.to_a

    visit registration_requests_path
    assert_text "Load more"
    page.execute_script("window.__systemTestLoaded = true")

    25.times { press "j" }
    assert_focused ordered[24]

    press "j"

    assert_no_text "Showing 25 of"
    assert_focused ordered[25]
    assert_match(/page=2/, page.current_url)
    assert page.evaluate_script("window.__systemTestLoaded"),
      "loading more with \"j\" reloaded the page instead of appending rows"

    press "j"
    assert_focused ordered[26]
  end

  test "claiming and releasing a request with the keyboard on the detail page updates it in place, without reloading the page" do
    assert_nil @pending.claimed_by
    visit registration_request_path(@pending)
    assert_text "@#{@pending.username}"

    # canary marker that get lost when page reloads
    page.execute_script("window.__systemTestLoaded = true")

    claim_and_wait_for_refresh_broadcast { press "c" }

    assert_equal @moderator, @pending.reload.claimed_by
    assert_text "You claimed this"
    assert page.evaluate_script("window.__systemTestLoaded"),
           "claiming with \"c\" reloaded the page instead of updating the row in place"

    claim_and_wait_for_refresh_broadcast { press "c" }

    assert_nil @pending.reload.claimed_by
    assert_text "Claim this request"
    assert page.evaluate_script("window.__systemTestLoaded"),
           "releasing with \"c\" reloaded the page instead of updating the row in place"
  end

  test "the claim button keeps focus when it replaces itself on the detail page" do
    button_id = ActionView::RecordIdentifier.dom_id(@pending, :claim_button)
    visit registration_request_path(@pending)
    assert_text "@#{@pending.username}"

    page.execute_script("document.getElementById(#{button_id.inspect}).focus()")
    claim_and_wait_for_refresh_broadcast { press :enter }

    assert_text "You claimed this"
    assert page.evaluate_script("document.activeElement.id === #{button_id.inspect}"),
           "claim button lost focus after claiming"

    claim_and_wait_for_refresh_broadcast { press :enter }

    assert_text "Claim this request"
    assert page.evaluate_script("document.activeElement.id === #{button_id.inspect}"),
           "claim button lost focus after releasing"
  end

  test "page thru the list on detail page" do
    pending_queue_scope = RegistrationRequests::Query.new(@moderator.instance.registration_requests, {}, viewer: @moderator).call
    ordered_ids = RegistrationRequests::Neighbors.new(pending_queue_scope, @pending).send(:ordered_ids)
    assert_not_empty ordered_ids
    ordered_requests = RegistrationRequest.where(id: ordered_ids).in_order_of(:id, ordered_ids).to_a

    first_in_list = ordered_requests.shift
    visit registration_request_path(first_in_list)
    assert_text "@#{first_in_list.username}"

    # canary marker that get lost when page reloads
    page.execute_script("window.__systemTestLoaded = true")

    ordered_requests.each do |request|
      press_and_wait "j"

      assert_text "@#{request.username}"
    end

    press_and_wait "j"

    assert_text "No more requests in this list — back to the queue."
    assert page.evaluate_script("window.__systemTestLoaded"),
           "navigating with \"j\" reloaded the page instead of updating it in place"
  end

  test "reject and next a whole list" do
    pending_queue_scope = RegistrationRequests::Query.new(@moderator.instance.registration_requests, {}, viewer: @moderator).call
    ordered_ids = RegistrationRequests::Neighbors.new(pending_queue_scope, @pending).send(:ordered_ids)
    assert_not_empty ordered_ids
    ordered_requests = RegistrationRequest.where(id: ordered_ids).in_order_of(:id, ordered_ids).to_a

    # DecisionsController pushes every reject straight to Mastodon (see its own
    # comment: "inline rather than queueing it"), so each request in the list
    # needs its own stub -- one real HTTP call per "r" press below.
    ordered_requests.each do |request|
      stub_decision(request.instance, id: request.mastodon_account_id, action: "reject")
    end

    first_in_list = ordered_requests.shift
    visit registration_request_path(first_in_list)
    assert_text "@#{first_in_list.username}"

    # canary marker that get lost when page reloads
    page.execute_script("window.__systemTestLoaded = true")

    rejected_request = first_in_list
    ordered_requests.each do |request|
      press_and_wait "r", :tab, :return

      rejected_request = request
      assert_text "@#{request.username}"
    end

    press_and_wait "r", :tab, :return

    assert_text "0 pending"
    assert_text "Rejected @#{rejected_request.username}"
    assert page.evaluate_script("window.__systemTestLoaded"),
           "navigating with \"j\" reloaded the page instead of updating it in place"
  end

  private

    # Capybara's `element.send_keys` refocuses its target element before every
    # call, which steals focus right back from the row "j" just selected. A
    # real key press does not do that, so this drives the same raw WebDriver
    # action a real keystroke would produce, aimed at whatever already has
    # focus.
    def press(*keys) = page.driver.browser.action.send_keys(*keys).perform

    def assert_focused(request)
      link_id = ActionView::RecordIdentifier.dom_id(request, :link)
      assert_selector "##{link_id}:focus"
    end

    def press_and_wait(*keys, wait: 0.3)
      press *keys
      sleep wait
    end

    # ClaimsController's own refresh broadcast is what would reload this same
    # tab: it's debounced (fired from a background thread, not the request),
    # and the test queue adapter only runs jobs enqueued while
    # perform_enqueued_jobs is listening. Staying in the block past the
    # debounce window is what lets that background enqueue -- and the
    # ActionCable broadcast it triggers -- actually happen before we check
    # whether the browser reacted to it.
    def claim_and_wait_for_refresh_broadcast(&block)
      perform_enqueued_jobs do
        block.call
        sleep REFRESH_DEBOUNCE_MARGIN
      end
      # Gives the browser a moment to receive and act on the broadcast that
      # just went out over the (real, same-process) Action Cable test adapter.
      sleep 0.3
    end
end
