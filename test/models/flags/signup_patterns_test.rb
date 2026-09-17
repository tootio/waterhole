require "test_helper"

# The two flags aimed at signup farms that rotate their addresses through
# residential proxies: similar_reason and signup_burst.
class Flags::SignupPatternsTest < ActiveSupport::TestCase
  TEMPLATE = "Hi, I am %s, a digital artist from Berlin and I would love to share my illustrations and meet other creative people here."

  setup do
    @alpha = instances(:alpha)   # participates
    @beta  = instances(:beta)    # participates
    @gamma = instances(:gamma)   # does not
  end

  def signup(instance, id, reason: "Just a quiet person who likes reading and writing about old maps and rivers.",
             username: "user#{id}", email: "#{username}@example.org", ip: "198.51.100.#{id % 250}", at: Time.current)
    instance.registration_requests.create!(mastodon_account_id: "sp#{id}", username:, email:, ip:,
      invite_request: reason, signed_up_at: at, confirmed: true, locale: "en")
  end

  def flag(request, rule) = request.tap(&:recompute_flags!).reload.flags.find_by(rule:)

  # --- fingerprints --------------------------------------------------------

  test "template variations fingerprint close, different reasons far apart" do
    a = ReasonFingerprint.call(format(TEMPLATE, "Anna"))
    b = ReasonFingerprint.call(format(TEMPLATE, "Marco"))
    other = ReasonFingerprint.call("Looking for a place to talk about open source databases, especially PostgreSQL tuning.")

    distance = ->(x, y) { ((x ^ y) & (2**64 - 1)).to_s(2).count("1") }
    assert_operator distance.(a, b), :<=, ReasonFingerprint::MAX_DISTANCE
    assert_operator distance.(a, other), :>, ReasonFingerprint::MAX_DISTANCE
  end

  test "short reasons get no fingerprint" do
    assert_nil ReasonFingerprint.call("I want to join please")
    assert_nil ReasonFingerprint.call(nil)
  end

  test "the fingerprint is keyed" do
    text = format(TEMPLATE, "Anna")
    original = ReasonFingerprint.call(text)
    with_hmac_key("another-key-entirely-different") do
      refute_equal original, ReasonFingerprint.call(text)
    end
  end

  def with_hmac_key(value)
    saved = ENV["WATERHOLE_SHARING_HMAC_KEY"]
    ENV["WATERHOLE_SHARING_HMAC_KEY"] = value
    yield
  ensure
    ENV["WATERHOLE_SHARING_HMAC_KEY"] = saved
  end

  # --- similar_reason --------------------------------------------------------

  test "a templated reason matches across participating instances, by domain only" do
    here  = signup(@alpha, 1, reason: format(TEMPLATE, "Anna"), username: "anna")
    local = signup(@alpha, 2, reason: format(TEMPLATE, "Marco"), username: "marco")
    signup(@beta, 3, reason: format(TEMPLATE, "Lena"), username: "lena")

    found = flag(here, "similar_reason")
    assert_equal "warning", found.severity, "several matches is the pattern of a farm"
    assert_equal 2, found.details["count"]
    assert_equal [ local.username ], found.details["usernames"]
    assert_equal [ "beta.example" ], found.details["instances"]
  end

  test "a single match is only info" do
    here = signup(@alpha, 1, reason: format(TEMPLATE, "Anna"))
    signup(@alpha, 2, reason: format(TEMPLATE, "Marco"))

    assert_equal "info", flag(here, "similar_reason").severity
  end

  test "a non-participating instance is compared with its own queue only, and not seen" do
    here = signup(@gamma, 1, reason: format(TEMPLATE, "Anna"))
    signup(@alpha, 2, reason: format(TEMPLATE, "Marco"))

    assert_nil flag(here, "similar_reason")
  end

  test "a new signup flags the requests it resembles" do
    earlier = signup(@beta, 1, reason: format(TEMPLATE, "Anna"))
    assert_nil flag(earlier, "similar_reason")

    perform_enqueued_jobs { signup(@alpha, 2, reason: format(TEMPLATE, "Marco")) }

    assert flag(earlier, "similar_reason")
  end

  # --- signup_burst ------------------------------------------------------------

  test "same-shaped signups within an hour, each from a different network, are a burst" do
    now = Time.current
    requests = 5.times.map do |i|
      signup(i.even? ? @alpha : @beta, 10 + i, username: "name#{rand(10..99)}", email: "x#{i}@gmail.com",
        ip: "203.0.113.#{10 + i}", at: now + i.minutes)
    end

    found = flag(requests.first, "signup_burst")
    assert_equal "info", found.severity
    assert_equal 5, found.details["count"]
    assert_equal 5, found.details["networks"]
    assert_equal "gmail.com a9 en", found.details["shape"]
    assert_equal [ "beta.example" ], found.details["instances"]
  end

  test "the same network repeated is not the proxy pattern" do
    now = Time.current
    requests = 5.times.map { |i| signup(@alpha, 20 + i, username: "name#{i}", email: "y#{i}@gmail.com", ip: "203.0.113.50", at: now + i.minutes) }

    assert_nil flag(requests.first, "signup_burst")
  end

  test "spread over more than the window is not a burst" do
    now = Time.current
    requests = 5.times.map { |i| signup(@alpha, 30 + i, username: "name#{i}", email: "z#{i}@gmail.com", ip: "203.0.113.#{60 + i}", at: now + (i * 40).minutes) }

    assert_nil flag(requests.first, "signup_burst")
  end

  test "the shape keeps separators and collapses runs" do
    assert_equal "a.a9", SignupShape.pattern("John.Smith84")
    assert_equal "a_a9", SignupShape.pattern("anna_berg2")
    assert_equal "gmail.com a9 -", SignupShape.call(email_domain: "gmail.com", username: "bob7", locale: nil)
  end

  include ActiveJob::TestHelper
end
