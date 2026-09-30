require "test_helper"

class RegistrationRequestsHelperTest < ActionView::TestCase
  # The phrase is rendered server-side so it is right without JavaScript; the
  # machine-readable datetime is what lets the browser keep it right.
  test "a past time reads as ago, and carries the instant it means" do
    time = 3.hours.ago
    html = relative_time(time)

    assert_includes html, "3 hours ago"
    assert_includes html, %(datetime="#{time.iso8601}")
    assert_includes html, %(data-controller="relative-time")
  end

  test "a deadline reads as a deadline rather than as elapsed time" do
    assert_includes relative_time(6.days.from_now), "in 6 days"
  end

  test "no time is a dash, not an empty element" do
    assert_equal "<span>—</span>", relative_time(nil)
  end

  test "a template mailto link is percent-encoded, with CRLF line breaks" do
    define_singleton_method(:current_moderator) { moderators(:avery) }
    template = EmailTemplate.new(name: "Ask", subject: "Q&A? {{username}}", body: "Line one\nLine + two")

    assert_equal "mailto:rowan@fastmail.com?subject=Q%26A%3F%20rowan&body=Line%20one%0D%0ALine%20%2B%20two",
      template_mailto(template, registration_requests(:pending_alpha))
  end

  test "a template without a subject leaves the subject out" do
    define_singleton_method(:current_moderator) { moderators(:avery) }
    template = EmailTemplate.new(name: "Ask", subject: "", body: "Hi")

    assert_equal "mailto:rowan@fastmail.com?body=Hi", template_mailto(template, registration_requests(:pending_alpha))
  end

  test "network research links cover the address, its AS and its country" do
    request = RegistrationRequest.new(ip: "203.0.113.5", ip_asn: 64500, ip_country: "DE")
    links = network_research_links(request)

    assert_equal [ "203.0.113.5", "AS64500", "Germany" ], links.keys
    assert_includes links["203.0.113.5"], [ "AbuseIPDB", "https://www.abuseipdb.com/check/203.0.113.5" ]
    assert_includes links["AS64500"], [ "bgp.tools", "https://bgp.tools/as/64500" ]
  end

  test "a malformed address never lands in a research link" do
    request = RegistrationRequest.new(ip: "203.0.113.5/../../evil", ip_country: "de<")

    assert_empty network_research_links(request)
  end

  test "country codes resolve to names, and unknown ones to nil" do
    assert_equal "Netherlands", Ip::Countries.name_for("nl")
    assert_nil Ip::Countries.name_for("ZZ")
  end
end
