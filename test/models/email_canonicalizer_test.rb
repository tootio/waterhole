require "test_helper"

class EmailCanonicalizerTest < ActiveSupport::TestCase
  # [description, input, expected]
  CASES = [
    # generic rules
    [ "plain", "spammer@example.com", "spammer@example.com" ],
    [ "plus tag", "spammer+1@example.com", "spammer@example.com" ],
    [ "multiple plus", "spammer+a+b@example.com", "spammer@example.com" ],
    [ "case", "Spammer+Foo@Example.COM", "spammer@example.com" ],
    [ "whitespace", " spammer+1@example.com\t", "spammer@example.com" ],
    [ "angle brackets", "<spammer+1@example.com>", "spammer@example.com" ],
    [ "trailing dot domain", "spammer@example.com.", "spammer@example.com" ],
    [ "dots kept by default", "s.pammer@example.com", "s.pammer@example.com" ],
    [ "hyphen kept by default", "s-pammer@example.com", "s-pammer@example.com" ],
    [ "only tag", "+tag@example.com", "+tag@example.com" ],
    [ "quoted local part", '"Spam+Mer"@example.com', '"spam+mer"@example.com' ],
    [ "at sign in quoted local part", '"a@b"@Example.com', '"a@b"@example.com' ],
    [ "unicode domain", "spammer@BÜCHER.example", "spammer@xn--bcher-kva.example" ],
    [ "punycode domain", "spammer@xn--bcher-kva.example", "spammer@xn--bcher-kva.example" ],
    [ "domain literal", "spammer+1@[192.0.2.1]", "spammer@[192.0.2.1]" ],

    # gmail
    [ "gmail dots", "s.p.a.m.m.e.r@gmail.com", "spammer@gmail.com" ],
    [ "gmail dots and tag", "S.pammer+x.y@GMail.com", "spammer@gmail.com" ],
    [ "googlemail", "s.pammer@googlemail.com", "spammer@gmail.com" ],
    [ "gmail only dots", "...@gmail.com", "...@gmail.com" ],
    [ "gmail lookalike domain", "s.pammer@gmail.co", "s.pammer@gmail.co" ],
    [ "gmail subdomain", "s.pammer@mail.gmail.com", "s.pammer@mail.gmail.com" ],

    # proton
    [ "proton separators", "s.pam-m_er+x@proton.me", "spammer@proton.me" ],
    [ "protonmail.com", "spammer@protonmail.com", "spammer@proton.me" ],
    [ "protonmail.ch", "spammer@protonmail.ch", "spammer@proton.me" ],
    [ "pm.me", "spammer@pm.me", "spammer@proton.me" ],

    # apple
    [ "icloud tag", "spammer+x@icloud.com", "spammer@icloud.com" ],
    [ "me.com", "spammer@me.com", "spammer@icloud.com" ],
    [ "mac.com", "spammer@mac.com", "spammer@icloud.com" ],
    [ "icloud keeps dots", "s.pammer@icloud.com", "s.pammer@icloud.com" ],

    # yahoo
    [ "yahoo disposable", "spammer-keyword@yahoo.com", "spammer@yahoo.com" ],
    [ "yahoo plus", "spammer+keyword@yahoo.de", "spammer@yahoo.de" ],
    [ "yahoo keeps dots", "s.pammer@yahoo.com", "s.pammer@yahoo.com" ],
    [ "yahoo domains not merged", "spammer@ymail.com", "spammer@ymail.com" ],

    # yandex
    [ "yandex dots are hyphens", "s.pammer@yandex.ru", "s-pammer@yandex.ru" ],
    [ "yandex hyphen", "s-pammer@yandex.ru", "s-pammer@yandex.ru" ],
    [ "yandex alias domain", "s.pammer+x@ya.ru", "s-pammer@yandex.ru" ],
    [ "yandex.com", "spammer@Yandex.com", "spammer@yandex.ru" ],

    # fastmail
    [ "fastmail subdomain", "anything@spammer.fastmail.com", "spammer@fastmail.com" ],
    [ "fastmail.fm subdomain", "Anything@Spammer.Fastmail.FM", "spammer@fastmail.fm" ],
    [ "fastmail plus", "spammer+x@fastmail.com", "spammer@fastmail.com" ],
    [ "fastmail deep subdomain", "x@a.b.fastmail.com", "x@a.b.fastmail.com" ],
    [ "fastmail lookalike", "x@spammerfastmail.com", "x@spammerfastmail.com" ],
    [ "fastmail keeps dots", "ju.les@fastmail.com", "ju.les@fastmail.com" ],

    # microsoft uses plain + tags and keeps dots
    [ "outlook", "s.pammer+x@outlook.com", "s.pammer@outlook.com" ],
    [ "hotmail not merged with outlook", "spammer@hotmail.com", "spammer@hotmail.com" ]
  ].freeze

  CASES.each do |description, input, expected|
    test "canonicalizes: #{description}" do
      assert_equal expected, EmailCanonicalizer.canonicalize(input)
    end
  end

  test "is idempotent" do
    [ "S.pammer+x@GoogleMail.com", "s.pam-m_er+x@pm.me", "s.pammer+x@ya.ru", "anything@spammer.fastmail.com",
      "spammer-keyword@yahoo.com", "spammer+1@BÜCHER.example", "+tag@example.com" ].each do |input|
      once = EmailCanonicalizer.canonicalize(input)
      assert_equal once, EmailCanonicalizer.canonicalize(once), "not idempotent for #{input.inspect}"
    end
  end

  # Unlike a plain normaliser, junk has no canonical form here: a made-up key
  # could match another junk value on another instance.
  test "returns nil for junk" do
    [ nil, "", "  ", "not-an-email", "No-At-Sign", "@nolocal.com", "nodomain@", "<>" ].each do |input|
      assert_nil EmailCanonicalizer.canonicalize(input), "expected nil for #{input.inspect}"
    end
  end

  # The disposable-domain flag and the queue filter need the domain as written.
  test "domain_of normalises the domain without merging provider aliases" do
    assert_equal "googlemail.com", EmailCanonicalizer.domain_of("A@GoogleMail.com.")
    assert_equal "xn--bcher-kva.example", EmailCanonicalizer.domain_of("a@BÜCHER.example")
    assert_equal "spammer.fastmail.com", EmailCanonicalizer.domain_of("x@spammer.fastmail.com")
    assert_nil EmailCanonicalizer.domain_of("nodomain@")
  end

  test "hashes are stable, and equal for addresses that canonicalise the same" do
    a = EmailCanonicalizer.hash_for("Ju.les+alpha@googlemail.com")
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
