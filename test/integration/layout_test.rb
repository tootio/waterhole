require "test_helper"

class LayoutTest < ActionDispatch::IntegrationTest
  # The sign-in and legal pages should not look like a different application.
  test "the header is present when signed out" do
    [ new_session_path, terms_path, verification_path ].each do |path|
      get path

      assert_select "header", true, "expected a header on #{path}"
      assert_select "header a", text: /Waterhole/
    end
  end

  # allow_unauthenticated_access used to skip the method that RESUMED the session,
  # not just the one that required it, so a signed-in moderator got the
  # signed-out header on every public page.
  test "public pages know you are signed in" do
    sign_in_as moderators(:avery)

    [ terms_path, privacy_path, imprint_path, verification_path ].each do |path|
      get path

      assert_response :success
      assert_select "header nav a", { text: "Queue", count: 1 },
        "expected the signed-in header on #{path}"
      assert_select "header a", { text: "Sign in", count: 0 },
        "#{path} should not offer sign-in to someone already signed in"
    end
  end

  test "signed out, the header offers a way in rather than moderator navigation" do
    get terms_path

    assert_select "header a[href=?]", new_session_path
    assert_select "header a[href=?]", verification_path
    assert_select "header nav", false, "moderator navigation has no meaning signed out"
  end

  test "the sign-in page does not offer a sign-in button" do
    get new_session_path

    # The logo legitimately links there when signed out; it is the *button* that
    # would be redundant.
    assert_select "header a", text: "Sign in", count: 0
  end

  test "the header carries the moderator navigation when signed in" do
    sign_in_as moderators(:avery)
    get root_path

    assert_select "header nav a", text: "Queue"
    assert_select "header nav a", text: "Watchwords"
    assert_select "header", /#{moderators(:avery).username}/
  end

  # On a phone the header becomes two rows -- identity and actions, then a nav
  # strip -- and returns to a single row from sm: up. These pin that contract,
  # because a utility-class tidy-up could undo it without breaking anything else.
  test "the nav forms its own full-width strip on mobile and rejoins the row at sm" do
    sign_in_as moderators(:avery)
    get root_path

    assert_select "header nav.w-full.sm\\:w-auto"
    assert_select "header nav.order-3.sm\\:order-2"
    assert_select "header nav.overflow-x-auto", true,
      "four tabs must scroll rather than wrap on a narrow phone"
  end

  test "nav labels do not break mid-phrase" do
    sign_in_as moderators(:avery)
    get root_path

    # "Sync history" wrapping onto two lines was what made the phone header
    # three rows tall.
    assert_select "header nav a.whitespace-nowrap", count: 4
  end

  test "the long handle is hidden on the smallest screens" do
    sign_in_as moderators(:avery)
    get root_path

    assert_select "header span.hidden.sm\\:inline", text: /#{moderators(:avery).username}/,
      count: 1
  end

  # Sticky footer: body is a flex column and <main> grows, so a short page pins
  # the footer to the bottom rather than leaving it floating mid-screen.
  test "the layout is a full-height flex column with a growing main" do
    get new_session_path

    assert_select "body.flex.min-h-dvh.flex-col"
    assert_select "main.flex-1"
    assert_select "footer.mt-auto"
  end

  test "the footer appears on every page, signed in or out" do
    get terms_path
    assert_select "footer a[href=?]", privacy_path

    sign_in_as moderators(:avery)
    get root_path
    assert_select "footer a[href=?]", imprint_path
  end

  # AGPL section 13: the footer is where a deployment offers its source.
  test "the footer links the source code when a source URL is configured" do
    ENV["WATERHOLE_SOURCE_URL"] = "https://example.org/waterhole"
    get new_session_path
    assert_select "footer a[href=?]", "https://example.org/waterhole", text: "Source code"
  ensure
    ENV.delete("WATERHOLE_SOURCE_URL")
  end

  test "the footer falls back to the upstream source when unset or not an http(s) URL" do
    [ nil, "", "javascript:alert(1)" ].each do |value|
      value ? ENV["WATERHOLE_SOURCE_URL"] = value : ENV.delete("WATERHOLE_SOURCE_URL")
      get new_session_path
      assert_select "footer a[href=?]", Waterhole::Deployment::DEFAULT_SOURCE_URL, text: "Source code"
    end
  ensure
    ENV.delete("WATERHOLE_SOURCE_URL")
  end
end
