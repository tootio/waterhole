require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  def badge_text(count) = Nokogiri::HTML5.fragment(queue_badge(count).to_s).text

  test "the badge shows the number waiting" do
    assert_equal "7", badge_text(7)
  end

  # A fourth digit would push the navigation around on a phone, and by then
  # the exact number has stopped changing anyone's next move.
  test "past ninety-nine the badge stops counting" do
    assert_equal "99", badge_text(99)
    assert_equal "99+", badge_text(100)
    assert_equal "99+", badge_text(4_213)
  end

  test "an empty queue has no badge at all, rather than a zero" do
    assert_nil queue_badge(0)
  end

  test "the badge says in words what the number means" do
    assert_includes queue_badge(7), %(aria-label="7 awaiting review")
  end
end
