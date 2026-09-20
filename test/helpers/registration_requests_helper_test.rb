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
end
