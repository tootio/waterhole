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
      assert_select "header nav a[href=?]", root_path, { count: 1 },
        "expected the signed-in header on #{path}"
      assert_select "header a", { text: "Sign in", count: 0 },
        "#{path} should not offer sign-in to someone already signed in"
    end
  end

  test "signed out, the header offers a way in rather than moderator navigation" do
    get terms_path

    assert_select "header nav a[href=?]", verification_path, text: "About"
    assert_select "header nav a[href=?]", new_session_path, text: "Sign in"
    assert_select "header nav a[href=?]", root_path, { count: 0 },
      "moderator navigation has no meaning signed out"
    assert_select "header details", false
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

    assert_select "header nav a[href=?]", root_path
    assert_select "header nav a[href=?]", herd_path(moderators(:avery).instance), text: "My herd"
    assert_select "header nav a", { text: "Watchwords", count: 0 }, "Watchwords live under My herd"
    assert_select "header nav a", { text: "Sync history", count: 0 }, "Sync history lives under My herd"
    assert_select "header button", { text: "Sync now", count: 0 }, "Sync now lives on the queue, by Last synced"
  end

  # One navigation, in reading order, so Tab walks the header the way it reads:
  # the account menu used to come first in the DOM and sit last on screen.
  test "the header holds one navigation, with the account menu at its end" do
    moderator = sign_in_as moderators(:avery)
    get root_path

    assert_select "header nav", 1
    assert_select "header nav > :last-child details[data-controller=dropdown]", 1
    order_classes = css_select("header [class]").flat_map { it["class"].split }.grep(/\A([\w-]+:)*order-/)
    assert_empty order_classes, "visual order must not be rearranged away from DOM order"
    assert_select "header details summary", text: /#{Regexp.escape(moderator.handle)}/
    assert_select "header details #account-menu" do
      assert_select "*", text: /#{Regexp.escape(moderator.handle)}/
      assert_select "form[action=?] button", session_path, text: "Sign out"
    end
  end

  test "without an avatar the menu shows the moderator's initial" do
    sign_in_as moderators(:avery)
    get root_path

    assert_select "header summary img", false
    assert_select "header summary span[aria-hidden=true]", text: "A"
  end

  test "with an avatar the menu shows our own copy of it" do
    moderator = sign_in_as moderators(:avery)
    moderator.create_avatar!(image: "\x89PNG\r\n\x1A\n".b, content_type: "image/png", source_url: "https://files.example/a.png")
    get root_path

    assert_select "header summary img[alt=''][src^=?]", "#{avatar_path}?v="
  end

  # Signing out has to stay reachable from the consent page, where nothing
  # else in the header is.
  test "before consent the header has the account menu and nothing else" do
    moderator = sign_in_as moderators(:avery)
    moderator.update!(consented_at: nil)
    get consent_path

    assert_select "header nav a", false
    assert_select "header details form[action=?]", session_path
  end

  test "the queue offers Sync now beside when it last synced" do
    sign_in_as moderators(:avery)
    get root_path

    assert_select "main form[action=?] button", sync_path, text: "Sync now"
  end

  test "My herd is the active nav item on its pages and shows their tabs" do
    moderator = sign_in_as moderators(:avery)
    own = herd_path(moderator.instance)

    [ own, keyword_rules_path, new_keyword_rule_path, email_templates_path, new_email_template_path, sync_runs_path ].each do |path|
      get path

      assert_select "header nav a.bg-stone-900", { text: "My herd", count: 1 }, "My herd should be active on #{path}"
      assert_select "header nav a.bg-stone-900", { text: "Herds", count: 0 }
      assert_select "main nav[aria-label='My herd'] a", 4
      assert_select "main nav[aria-label='My herd'] a[aria-current=page]", 1
    end
  end

  test "Herds, not My herd, is active on the herds list and on another herd's page" do
    sign_in_as moderators(:avery)

    [ herds_path, herd_path(instances(:beta)) ].each do |path|
      get path

      assert_select "header nav a.bg-stone-900", { text: "Herds", count: 1 }, "Herds should be active on #{path}"
      assert_select "header nav a.bg-stone-900", { text: "My herd", count: 0 }
      assert_select "main nav[aria-label='My herd']", false
    end
  end

  # One row at every width. These pin that contract, because a utility-class
  # tidy-up could undo it without breaking anything else.
  test "the nav fits one row on a phone" do
    sign_in_as moderators(:avery)
    get root_path

    assert_select "header nav ul.overflow-x-auto", true,
      "the links must scroll rather than wrap on a narrow phone"
    assert_select "header a[href=?] span.sr-only.sm\\:not-sr-only", root_path, text: "Waterhole"
  end

  test "nav labels do not break mid-phrase" do
    sign_in_as moderators(:avery)
    get root_path

    # "Sync history" wrapping onto two lines was what made the phone header
    # three rows tall; "My herd" could do the same.
    assert_select "header nav a.whitespace-nowrap", count: 3
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
    assert_select "footer", text: /Waterhole #{Regexp.escape(Waterhole::Deployment.version)}/

    sign_in_as moderators(:avery)
    get root_path
    assert_select "footer a[href=?]", imprint_path
    assert_select "footer", text: /Waterhole #{Regexp.escape(Waterhole::Deployment.version)}/
  end

  test "the footer shows the configured version" do
    ENV["WATERHOLE_VERSION"] = "v1.2.3"
    get new_session_path
    assert_select "footer", text: /Waterhole v1.2.3/
  ensure
    ENV.delete("WATERHOLE_VERSION")
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
  test "the footer links the issues page to report a problem, when there is one" do
    get new_session_path
    assert_select "footer a[href=?]",
      "#{Waterhole::Deployment::DEFAULT_SOURCE_URL}/issues/new?template=bug_report.yml&version=#{CGI.escape(Waterhole::Deployment.version)}",
      text: "Report a problem"

    # A fork may not have our issue forms.
    ENV["WATERHOLE_SOURCE_URL"] = "https://github.com/someone/waterhole"
    get new_session_path
    assert_select "footer a[href=?]", "https://github.com/someone/waterhole/issues", text: "Report a problem"

    ENV["WATERHOLE_SOURCE_URL"] = "https://example.org/waterhole"
    get new_session_path
    assert_select "footer a", { count: 0, text: "Report a problem" }
  ensure
    ENV.delete("WATERHOLE_SOURCE_URL")
  end

  # On every page but the queue itself, this badge is the only sign that work
  # has arrived -- so it has to be right, and it has to be live.
  test "the Queue nav item badges how many requests await review" do
    waiting = moderators(:avery).instance.registration_requests.awaiting_review.count
    assert waiting.positive?, "the fixtures should leave something in the queue"
    sign_in_as moderators(:avery)

    get keyword_rules_path

    assert_select "header nav a[href=?] #queue_badge span", root_path, text: waiting.to_s
  end

  test "an empty queue shows no badge rather than a zero" do
    moderators(:avery).instance.registration_requests.awaiting_review.update_all(status: "approved")
    sign_in_as moderators(:avery)

    get keyword_rules_path

    assert_select "#queue_badge", count: 1, text: ""
    assert_select "#queue_badge span", count: 0
  end

  test "the badge counts only this instance's requests" do
    sign_in_as moderators(:casey)
    casey_waiting = moderators(:casey).instance.registration_requests.awaiting_review.count

    get keyword_rules_path

    assert_select "header nav a[href=?] #queue_badge span", root_path, text: casey_waiting.to_s
    assert_not_equal moderators(:avery).instance.registration_requests.awaiting_review.count,
      casey_waiting, "the fixtures should differ per instance for this to mean anything"
  end

  # The badge has a stream of its own, carrying replacements of that one
  # element. Subscribing the layout to the queue's refresh stream instead would
  # keep the count just as true and refresh every page to do it -- including one
  # a moderator is typing into.
  test "pages other than the queue subscribe only to the badge stream" do
    sign_in_as moderators(:avery)

    get keyword_rules_path

    assert_select "turbo-cable-stream-source", count: 1
    assert_select "#queue_badge", count: 1
  end

  test "the queue keeps its own stream, since the layout no longer carries it" do
    sign_in_as moderators(:avery)

    get root_path

    assert_select "turbo-cable-stream-source", { count: 2 },
      "the badge's stream and the queue's own"
  end
  # The shell only. Pinning dark: classes on feature views would make every palette
  # tweak a test edit; this catches the regression that matters -- a build or a
  # sweep that strips the variants wholesale.
  test "the page shell carries its dark-mode counterparts" do
    sign_in_as moderators(:avery)
    get root_path

    assert_select "body[class*=?]", "dark:bg-stone-950"
    assert_select "body[class*=?]", "dark:text-stone-100"
    assert_select "header[class*=?]", "dark:bg-stone-900"
  end

  # Nothing tells the browser to paint its own chrome dark otherwise, and a dark
  # page with white checkboxes and a bright scrollbar reads as broken.
  test "the browser is told the page supports both schemes" do
    get new_session_path

    assert_select %(meta[name="theme-color"][media="(prefers-color-scheme: dark)"]), count: 1
  end
end
