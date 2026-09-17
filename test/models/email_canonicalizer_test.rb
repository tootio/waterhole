require "test_helper"

class EmailCanonicalizerTest < ActiveSupport::TestCase
  test "strips plus extensions" do
    assert_equal "jules@fastmail.com", EmailCanonicalizer.canonicalize("jules+waterhole@fastmail.com")
  end

  test "lowercases" do
    assert_equal "jules@fastmail.com", EmailCanonicalizer.canonicalize("Jules@FastMail.com")
  end

  test "strips dots only for providers that ignore them" do
    assert_equal "jules@gmail.com", EmailCanonicalizer.canonicalize("ju.les@gmail.com")
    # Most providers treat dots as significant, so removing them elsewhere would
    # merge two genuinely different people.
    assert_equal "ju.les@fastmail.com", EmailCanonicalizer.canonicalize("ju.les@fastmail.com")
  end

  test "handles plus and dots together" do
    assert_equal "jules@gmail.com", EmailCanonicalizer.canonicalize("Ju.les+alpha@Gmail.com")
  end

  test "returns nil for junk" do
    [ nil, "", "  ", "not-an-email", "@nolocal.com", "nodomain@" ].each do |input|
      assert_nil EmailCanonicalizer.canonicalize(input), "expected nil for #{input.inspect}"
    end
  end

  test "hashes are stable, and equal for addresses that canonicalise the same" do
    a = EmailCanonicalizer.hash_for("Ju.les+alpha@gmail.com")
    b = EmailCanonicalizer.hash_for("jules@gmail.com")

    assert_equal a, b
    assert_equal 64, a.length
  end

  test "different people hash differently" do
    refute_equal EmailCanonicalizer.hash_for("a@example.org"), EmailCanonicalizer.hash_for("b@example.org")
  end

  test "the hash is keyed, not a bare digest of the address" do
    # The space of email addresses is small enough to enumerate, so an unsalted
    # digest would be trivially reversible.
    refute_equal Digest::SHA256.hexdigest("jules@gmail.com"), EmailCanonicalizer.hash_for("jules@gmail.com")
  end
end
