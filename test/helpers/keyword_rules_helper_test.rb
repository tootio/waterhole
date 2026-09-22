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

    assert_equal "<mark>crypto</mark> <mark>air</mark>drop", result
    assert result.html_safe?
  end

  test "handles multiple rules matching the exact same token without duplicating mark tags" do
    @instance.keyword_rules.create!(pattern: "spam", match_type: "word", severity: "warning")
    @instance.keyword_rules.create!(pattern: "spam", match_type: "substring", severity: "warning")

    result = highlight_keywords("stop spam now")

    assert_equal "stop <mark>spam</mark> now", result
    assert result.html_safe?
  end

  test "handles multiple rules matching overlapping substrings by merging intervals" do
    @instance.keyword_rules.create!(pattern: "cryptocurrency", match_type: "word", severity: "warning")
    @instance.keyword_rules.create!(pattern: "crypto", match_type: "substring", severity: "warning")

    result = highlight_keywords("invest in cryptocurrency")

    assert_equal "invest in <mark>cryptocurrency</mark>", result
    assert result.html_safe?
  end

  test "handles multiple rules matching touching or distinct parts of the same token" do
    @instance.keyword_rules.create!(pattern: "super", match_type: "substring", severity: "warning")
    @instance.keyword_rules.create!(pattern: "hero", match_type: "substring", severity: "warning")

    result = highlight_keywords("look at the superhero")

    assert_equal "look at the <mark>superhero</mark>", result
    assert result.html_safe?
  end

  test "handles distinct non-touching substring matches within a token" do
    @instance.keyword_rules.create!(pattern: "super", match_type: "substring", severity: "warning")
    @instance.keyword_rules.create!(pattern: "man", match_type: "substring", severity: "warning")

    result = highlight_keywords("superduperman")

    assert_equal "<mark>super</mark>duper<mark>man</mark>", result
    assert result.html_safe?
  end

  test "escapes unescaped HTML content safely while highlighting matches" do
    @instance.keyword_rules.create!(pattern: "alert", match_type: "word", severity: "warning")

    result = highlight_keywords("<script>alert('xss')</script>")

    assert_equal "&lt;script&gt;<mark>alert</mark>(&#39;xss&#39;)&lt;/script&gt;", result
    assert result.html_safe?
  end

  test "handles keyword rules matching literal tag names without corrupting existing mark tags" do
    @instance.keyword_rules.create!(pattern: "crypto", match_type: "word", severity: "warning")
    @instance.keyword_rules.create!(pattern: "mark", match_type: "substring", severity: "warning")

    result = highlight_keywords("crypto market")

    assert_equal "<mark>crypto</mark> <mark>mark</mark>et", result
    assert result.html_safe?
  end

  test "ignores disabled rules" do
    @instance.keyword_rules.create!(pattern: "crypto", match_type: "word", severity: "warning", enabled: false)

    result = highlight_keywords("crypto enthusiast")

    assert_equal "crypto enthusiast", result
  end

  test "split_into_parts breaks text into matching and non-matching Part objects" do
    parts = split_into_parts("superduperman", [ [ 0, 5 ], [ 10, 13 ] ])

    assert_equal 3, parts.size
    assert_equal "super", parts[0].text
    assert parts[0].mark?
    assert_equal "duper", parts[1].text
    refute parts[1].mark?
    assert_equal "man", parts[2].text
    assert parts[2].mark?
  end

  test "split_into_parts handles empty text or empty matches" do
    assert_equal [], split_into_parts("", [])
    assert_equal [ KeywordRulesHelper::Part.new(text: "hello", mark?: false) ], split_into_parts("hello", [])
  end
end
