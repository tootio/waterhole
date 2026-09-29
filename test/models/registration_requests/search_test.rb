require "test_helper"

class RegistrationRequests::SearchTest < ActiveSupport::TestCase
  setup do
    @rowan   = registration_requests(:pending_alpha)  # rowan@fastmail.com, "…smaller server…"
    @claimed = registration_requests(:claimed_alpha)  # claimed@example.org, "A perfectly reasonable…"
    @scope   = instances(:alpha).registration_requests.where(id: [ @rowan.id, @claimed.id ])
  end

  def search(text) = @scope.search(text).to_a

  test "parses words, properties, negation and quoted phrases" do
    terms = RegistrationRequests::Search.parse(%(crypto -domain:gmail.com reason:"free followers" Bio:x))

    assert_equal [
      [ nil, "crypto", false ], [ "domain", "gmail.com", true ],
      [ "reason", "free followers", false ], [ "bio", "x", false ]
    ], terms.map { [ it.property, it.value, it.negated ] }
  end

  test "anything that is not a known property is plain text" do
    terms = RegistrationRequests::Search.parse("http://spam.example colour: - \"unclosed")

    assert_equal [ "http://spam.example", "colour:", "-", "unclosed" ], terms.map(&:value)
    assert terms.all? { it.property.nil? && !it.negated }
  end

  test "a plain word matches any of the shown fields, and words combine" do
    assert_equal [ @rowan ], search("fastmail")
    assert_equal [ @rowan ], search("smaller community")
    assert_empty search("smaller perfectly")
  end

  test "a property narrows to its field" do
    assert_equal [ @rowan ], search("domain:fastmail")
    assert_empty search("username:fastmail")
    assert_equal [ @claimed ], search(%(reason:"perfectly reasonable"))
  end

  # An empty field must count as "does not contain", not drop out as NULL.
  test "a negated term keeps requests whose field is empty" do
    @claimed.update_columns(display_name: nil)

    assert_equal [ @claimed ], search("-domain:fastmail")
    assert_equal [ @rowan, @claimed ].to_set, search("-name:anything").to_set
  end

  test "flag: takes the rule name or its label" do
    @rowan.flags.create!(rule: "tor_relay", severity: "info")

    assert_equal [ @rowan ], search("flag:tor_relay")
    assert_equal [ @rowan ], search(%(flag:"Tor relay"))
    assert_equal [ @claimed ], search("-flag:tor-relay")
    assert_empty search("flag:no_such_flag")
    assert_equal 2, search("-flag:no_such_flag").size
  end

  test "a flag term can carry a severity, quoted or not" do
    terms = RegistrationRequests::Search.parse(%(flag:keyword_hit@warning flag:"Tor relay"@info flag:x@nope reason:"a b"@warning))

    assert_equal [
      [ "flag", "keyword_hit", "warning" ], [ "flag", "Tor relay", "info" ],
      [ "flag", "x@nope", nil ], [ "reason", "a b@warning", nil ]
    ], terms.map { [ it.property, it.value, it.severity ] }
  end

  test "severity: takes a severity name, anything else is plain text" do
    terms = RegistrationRequests::Search.parse("Severity:Warning -severity:critical severity:bogus")

    assert_equal [ [ "severity", "warning", false ], [ "severity", "critical", true ], [ nil, "severity:bogus", false ] ],
      terms.map { [ it.property, it.value, it.negated ] }
  end

  test "severities compare on the flag itself" do
    @rowan.flags.create!(rule: "keyword_hit", severity: "info")
    @rowan.flags.create!(rule: "tor_relay", severity: "critical")
    @claimed.flags.create!(rule: "keyword_hit", severity: "warning")

    assert_equal [ @claimed ], search("flag:keyword_hit@warning")
    assert_equal [ @rowan, @claimed ].to_set, search("flag:keyword_hit@info").to_set
    assert_equal [ @rowan ], search("-flag:keyword_hit@warning")
    assert_equal [ @rowan ], search("severity:critical")
    assert_equal [ @claimed ], search("-severity:critical")
  end
end
