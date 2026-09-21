require "test_helper"

class QueueTest < ActionDispatch::IntegrationTest
  setup { @moderator = moderators(:avery) }

  test "signed out visitors are sent to sign in" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "the queue lists this instance's pending requests" do
    sign_in_as @moderator
    get root_path

    assert_response :success
    assert_select "body", /rowan/
  end

  # The security boundary: a moderator must not be able to address another
  # instance's records, even by guessing an id.
  test "a moderator cannot open another instance's request" do
    sign_in_as @moderator
    other = registration_requests(:other_instance)

    get registration_request_path(other)

    assert_response :not_found
  end

  test "a moderator cannot act on another instance's request" do
    sign_in_as @moderator
    other = registration_requests(:other_instance)

    post registration_request_claim_path(other)

    assert_response :not_found
    assert_nil other.reload.claimed_by
  end

  # Regression: the rows sit inside the "queue" Turbo Frame, which exists for
  # filtering and paging. A row link that does not break out of it tries to load
  # the detail page into that frame, and since the detail page has no "queue"
  # frame the list just empties itself.
  test "row links escape the queue frame" do
    sign_in_as @moderator
    get root_path

    assert_response :success
    assert_select "turbo-frame#queue a[href=?]", registration_request_path(registration_requests(:pending_alpha)) do |links|
      assert_equal "_top", links.first["data-turbo-frame"],
        "a row link inside the queue frame must target _top"
      assert_match(%r{\A/requests/\d+/claim\z}, links.first["data-claim-url"])
      assert_equal "false", links.first["data-claimed-by-me"]
    end
  end

  test "filtering by flag narrows the queue" do
    sign_in_as @moderator
    registration_requests(:jules_alpha).recompute_flags!

    get root_path, params: { flag: "email_active_elsewhere" }

    assert_response :success
    assert_select "body", /jules_alpha/
    assert_select "body", { count: 0, text: /rowan/ }, "rowan has no such flag"
  end

  test "a revoked instance ends the session at the very next request" do
    sign_in_as @moderator
    get root_path
    assert_response :success

    @moderator.instance.update!(status: "revoked")

    get root_path
    assert_redirected_to new_session_path
    assert_match(/no longer authorised/, flash[:alert])
  end

  test "a blocked instance says so plainly" do
    sign_in_as @moderator
    @moderator.instance.update!(status: "blocked")

    get root_path

    assert_redirected_to new_session_path
    assert_match(/no longer served/, flash[:alert])
  end

  # As in Mastodon, which only tells staff about a pending account once its
  # email is confirmed.
  test "unconfirmed signups are hidden by default, counted, and one filter away" do
    sign_in_as @moderator
    @moderator.instance.registration_requests.create!(mastodon_account_id: "9401",
      username: "not_yet_confirmed", signed_up_at: 1.hour.ago, confirmed: false,
      invite_request: "I have not clicked the link in the email yet.")

    get root_path
    assert_select "body", { count: 0, text: /not_yet_confirmed/ }
    assert_select "a[href=?]", root_path(email: "unconfirmed"), text: "1 waiting for email confirmation"

    get root_path, params: { email: "unconfirmed" }
    assert_select "li", /not_yet_confirmed/
    assert_select "li span", "Email not confirmed"
    assert_select "body", { count: 0, text: /rowan/ }, "confirmed ones are not in this view"
  end

  # Regression: the pagination links were built by handing url_for the raw
  # query string, so ?host= and ?protocol= rewrote them into another origin or
  # a javascript: URL.
  test "pagination links stay on this site and carry only the filters" do
    sign_in_as @moderator
    30.times do |i|
      @moderator.instance.registration_requests.create!(mastodon_account_id: "95#{i}",
        username: "paged#{i}", signed_up_at: (i + 1).minutes.ago, confirmed: true)
    end

    get root_path, params: { host: "evil.example", protocol: "javascript", sort: "oldest" }

    assert_response :success
    assert_select "a", text: "Older →" do |links|
      href = links.first["href"]
      assert href.start_with?("/"), "expected a path, got #{href.inspect}"
      refute_match(/evil|javascript/, href)
      assert_match(/sort=oldest/, href)
      assert_match(/page=2/, href)
    end
  end

  test "an empty default queue congratulates the moderator instead of showing a dull empty state" do
    sign_in_as @moderator
    @moderator.instance.registration_requests.destroy_all

    get root_path

    assert_response :success
    assert_select "body", /waterhole is quiet/
    assert_select "body", { count: 0, text: /Nothing here/ }
  end

  test "an empty filtered queue still shows the plain empty state" do
    sign_in_as @moderator
    @moderator.instance.registration_requests.destroy_all

    get root_path, params: { search: "nobody-matches-this" }

    assert_response :success
    assert_select "body", /Nothing here/
    assert_select "body", { count: 0, text: /waterhole is quiet/ }
  end

  test "flags are shown by their labels, not their rule names" do
    sign_in_as @moderator
    request = registration_requests(:pending_alpha)
    request.flags.create!(rule: "ip_active_elsewhere", severity: "info", details: { "count" => 1, "instances" => [ "beta.example" ] })

    get root_path
    assert_select "li span", "IP active elsewhere"
    assert_select "select[name=flag] option[value=datacenter_asn]", "Datacenter ASN"

    get registration_request_path(request)
    # The label's <p> also carries the "About this flag" link, so match by
    # substring rather than exact text.
    assert_select "p", /IP active elsewhere/
    assert_select "body", { count: 0, text: /Ip active elsewhere/ }
  end
end
