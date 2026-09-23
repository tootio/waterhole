require "test_helper"

class KeywordRulesHelperTest < ActionView::TestCase
  setup do
    @instance = instances(:alpha)
    @moderator = moderators(:avery)
    Current.session = Session.new(moderator: @moderator)
  end

  teardown do
    Current.session = nil
  end

  test "returns unchanged text when no keyword rules exist" do
    assert_equal "hello world", highlight_keywords("hello world")
  end

  test "returns nil/blank when input is nil or blank" do
    assert_nil highlight_keywords(nil)
    assert_equal "", highlight_keywords("")
  end

  test "highlights matches across multiple enabled rules" do
    @instance.keyword_rules.create!(pattern: "crypto", match_type: "word", severity: "warning")
    @instance.keyword_rules.create!(pattern: "air", match_type: "substring", severity: "warning")

    result = highlight_keywords("crypto airdrop")

    assert_equal "#{mark("crypto", :warning)} #{mark("air", :warning)}drop", result
    assert result.html_safe?
  end

  test "colours each match by its rule's severity" do
    @instance.keyword_rules.create!(pattern: "crypto", match_type: "word", severity: "critical")
    @instance.keyword_rules.create!(pattern: "air", match_type: "substring", severity: "info")

    assert_equal "#{mark("crypto", :critical)} #{mark("air", :info)}drop", highlight_keywords("crypto airdrop")
  end

  test "handles multiple rules matching the exact same token without duplicating mark tags" do
    @instance.keyword_rules.create!(pattern: "spam", match_type: "word", severity: "warning")
    @instance.keyword_rules.create!(pattern: "spam", match_type: "substring", severity: "warning")

    result = highlight_keywords("stop spam now")

    assert_equal "stop #{mark("spam", :warning)} now", result
    assert result.html_safe?
  end

  test "the highest severity wins when rules match the exact same interval" do
    @instance.keyword_rules.create!(pattern: "spam", match_type: "word", severity: "info")
    @instance.keyword_rules.create!(pattern: "spam", match_type: "substring", severity: "critical")
    @instance.keyword_rules.create!(pattern: "sp.m", match_type: "regex", severity: "warning")

    assert_equal "stop #{mark("spam", :critical)} now", highlight_keywords("stop spam now")
  end

  test "a strictly nested match wins over the match around it, whatever the severities" do
    @instance.keyword_rules.create!(pattern: "cryptocurrency", match_type: "word", severity: "critical")
    @instance.keyword_rules.create!(pattern: "ptocur", match_type: "substring", severity: "info")

    assert_equal "invest in #{mark("cry", :critical, joined: %i[ end ])}#{mark("ptocur", :info, joined: %i[ start end ])}#{mark("rency", :critical, joined: %i[ start ])}",
      highlight_keywords("invest in cryptocurrency")
  end

  test "a nested match sharing the start is decided by severity" do
    @instance.keyword_rules.create!(pattern: "cryptocurrency", match_type: "word", severity: "critical")
    @instance.keyword_rules.create!(pattern: "crypto", match_type: "substring", severity: "info")

    assert_equal "invest in #{mark("cryptocurrency", :critical)}", highlight_keywords("invest in cryptocurrency")
  end

  test "a nested match sharing the end with higher severity wins its part" do
    @instance.keyword_rules.create!(pattern: "cryptocurrency", match_type: "word", severity: "info")
    @instance.keyword_rules.create!(pattern: "currency", match_type: "substring", severity: "critical")

    assert_equal "invest in #{mark("crypto", :info, joined: %i[ end ])}#{mark("currency", :critical, joined: %i[ start ])}", highlight_keywords("invest in cryptocurrency")
  end

  test "a nested match sharing a boundary with equal severity keeps its own mark" do
    @instance.keyword_rules.create!(pattern: "cryptocurrency", match_type: "word", severity: "warning")
    @instance.keyword_rules.create!(pattern: "crypto", match_type: "substring", severity: "warning")

    assert_equal "invest in #{mark("crypto", :warning, joined: %i[ end ])}#{mark("currency", :warning, joined: %i[ start ])}", highlight_keywords("invest in cryptocurrency")
  end

  test "partially overlapping matches: the highest severity takes the overlap" do
    @instance.keyword_rules.create!(pattern: "supe", match_type: "substring", severity: "critical")
    @instance.keyword_rules.create!(pattern: "perm", match_type: "substring", severity: "info")

    assert_equal "#{mark("supe", :critical, joined: %i[ end ])}#{mark("rm", :info, joined: %i[ start ])}an", highlight_keywords("superman")
  end

  test "partially overlapping matches of equal severity: the first one takes the overlap" do
    @instance.keyword_rules.create!(pattern: "supe", match_type: "substring", severity: "warning")
    @instance.keyword_rules.create!(pattern: "perm", match_type: "substring", severity: "warning")

    assert_equal "#{mark("supe", :warning, joined: %i[ end ])}#{mark("rm", :warning, joined: %i[ start ])}an", highlight_keywords("superman")
  end

  test "touching matches keep separate marks" do
    @instance.keyword_rules.create!(pattern: "super", match_type: "substring", severity: "warning")
    @instance.keyword_rules.create!(pattern: "hero", match_type: "substring", severity: "warning")

    result = highlight_keywords("look at the superhero")

    assert_equal "look at the #{mark("super", :warning, joined: %i[ end ])}#{mark("hero", :warning, joined: %i[ start ])}", result
    assert result.html_safe?
  end

  test "handles distinct non-touching substring matches within a token" do
    @instance.keyword_rules.create!(pattern: "super", match_type: "substring", severity: "warning")
    @instance.keyword_rules.create!(pattern: "man", match_type: "substring", severity: "warning")

    result = highlight_keywords("superduperman")

    assert_equal "#{mark("super", :warning)}duper#{mark("man", :warning)}", result
    assert result.html_safe?
  end

  test "resolve_match_intervals: strict nesting splits the outer match" do
    assert_equal [ [ 0, 2, "info" ], [ 2, 3, "warning" ], [ 3, 5, "info" ] ],
      resolve_match_intervals([ match(0, 5, :info), match(2, 3, :warning) ])
    assert_equal [ [ 0, 2, "critical" ], [ 2, 3, "info" ], [ 3, 5, "critical" ] ],
      resolve_match_intervals([ match(0, 5, :critical), match(2, 3, :info) ])
  end

  test "resolve_match_intervals: partial overlap goes to the highest severity" do
    assert_equal [ [ 0, 4, "critical" ], [ 4, 5, "info" ] ],
      resolve_match_intervals([ match(0, 4, :critical), match(2, 5, :info) ])
    assert_equal [ [ 0, 2, "info" ], [ 2, 5, "critical" ] ],
      resolve_match_intervals([ match(0, 4, :info), match(2, 5, :critical) ])
  end

  test "resolve_match_intervals: innermost first, then severity, for chains of overlaps" do
    # B is strictly inside A and beats it; C overlaps B and beats it on severity;
    # A overlaps C, where A wins on severity.
    a = match(0, 10, :critical)
    b = match(2, 6, :info)
    c = match(5, 12, :warning)

    assert_equal [ [ 0, 2, "critical" ], [ 2, 5, "info" ], [ 5, 6, "warning" ], [ 6, 10, "critical" ], [ 10, 12, "warning" ] ],
      resolve_match_intervals([ a, b, c ])
  end

  test "resolve_match_intervals: disjoint matches are kept as they are" do
    assert_equal [ [ 0, 2, "info" ], [ 4, 6, "critical" ] ],
      resolve_match_intervals([ match(4, 6, :critical), match(0, 2, :info) ])
  end

  test "escapes unescaped HTML content safely while highlighting matches" do
    @instance.keyword_rules.create!(pattern: "alert", match_type: "word", severity: "warning")

    result = highlight_keywords("<script>alert('xss')</script>")

    assert_equal "&lt;script&gt;#{mark("alert", :warning)}(&#39;xss&#39;)&lt;/script&gt;", result
    assert result.html_safe?
  end

  test "handles keyword rules matching literal tag names without corrupting existing mark tags" do
    @instance.keyword_rules.create!(pattern: "crypto", match_type: "word", severity: "warning")
    @instance.keyword_rules.create!(pattern: "mark", match_type: "substring", severity: "warning")

    result = highlight_keywords("crypto market")

    assert_equal "#{mark("crypto", :warning)} #{mark("mark", :warning)}et", result
    assert result.html_safe?
  end

  test "ignores disabled rules" do
    @instance.keyword_rules.create!(pattern: "crypto", match_type: "word", severity: "warning", enabled: false)

    result = highlight_keywords("crypto enthusiast")

    assert_equal "crypto enthusiast", result
  end

  test "split_into_parts breaks text into matching and non-matching Part objects" do
    parts = split_into_parts("superduperman", [ [ 0, 5, "warning" ], [ 10, 13, "info" ] ])

    assert_equal 3, parts.size
    assert_equal "super", parts[0].text
    assert parts[0].mark?
    assert_equal "warning", parts[0].severity
    assert_equal "duper", parts[1].text
    refute parts[1].mark?
    assert_equal "man", parts[2].text
    assert parts[2].mark?
    assert_equal "info", parts[2].severity
  end

  test "split_into_parts handles empty text or empty matches" do
    assert_equal [], split_into_parts("", [])
    assert_equal [ KeywordRulesHelper::Part.new(text: "hello", severity: nil) ], split_into_parts("hello", [])
  end

  private

  def mark(text, severity, joined: [])
    classes = [ KeywordRulesHelper::MARK_STYLES.fetch(severity.to_s), *joined.map { "text-marker-joined-#{it}" } ]
    %(<mark class="#{classes.join(" ")}">#{text}</mark>)
  end

  def match(start, stop, severity)
    KeywordRulesHelper::Match.new(start, stop, severity.to_s)
  end
end
