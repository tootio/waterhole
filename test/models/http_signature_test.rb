require "test_helper"

class HttpSignatureTest < ActiveSupport::TestCase
  URL = "https://waterhole.test/identity_challenges/abc".freeze

  def request_for(url = URL, headers: mastodon_signed_headers(URL))
    env = headers.transform_keys { "HTTP_#{it.upcase.tr("-", "_")}" }
    ActionDispatch::Request.new(Rack::MockRequest.env_for(url, env))
  end

  def pem(key = actor_key) = key.public_to_pem

  test "a request signed as Mastodon signs is verified" do
    assert HttpSignature.verified?(request_for, pem)
  end

  test "every Mastodon release line's signature is verified" do
    MastodonStubs::MASTODON_SIGNED_HEADERS.each_key do |mastodon|
      assert HttpSignature.verified?(request_for(headers: mastodon_signed_headers(URL, mastodon:)), pem), mastodon
    end
  end

  # Releases up to 4.5 sign Accept: a proxy that rewrites it breaks the proof.
  test "a signed Accept header that was changed on the way is not" do
    headers = mastodon_signed_headers(URL, mastodon: "4.4-4.5").merge("Accept" => "*/*")
    refute HttpSignature.verified?(request_for(headers:), pem)
  end

  test "a signature by another key is not" do
    refute HttpSignature.verified?(request_for, pem(actor_key(:replacement)))
  end

  test "a signature for another path is not" do
    refute HttpSignature.verified?(request_for("https://waterhole.test/identity_challenges/xyz"), pem)
  end

  test "an old signature is not" do
    refute HttpSignature.verified?(request_for(headers: mastodon_signed_headers(URL, date: 2.hours.ago)), pem)
  end

  test "a signature that leaves out the request target is not" do
    headers = mastodon_signed_headers(URL)
    headers["Signature"] = headers["Signature"].sub('headers="host date (request-target)"', 'headers="host date"')
    refute HttpSignature.verified?(request_for(headers:), pem)
  end

  test "the header is read as Mastodon reads it" do
    assert_equal({ "keyId" => "k", "algorithm" => "rsa-sha256", "headers" => "host date" },
      HttpSignature.parse('Signature keyId="k" , algorithm=rsa-sha256,headers="host date"'))
    assert_equal({ "a" => 'x\"y' }, HttpSignature.parse('a="x\"y"'))
  end

  test "a header that does not parse completely is refused" do
    assert_nil HttpSignature.parse('keyId="k",signature="s",keyId="other"'), "duplicate keys"
    assert_nil HttpSignature.parse('keyId="k" signature="s"'), "missing comma"
    assert_nil HttpSignature.parse('keyId="k",'), "trailing comma"
    assert_nil HttpSignature.parse("")
  end

  test "a duplicated parameter fails verification even when one copy is valid" do
    headers = mastodon_signed_headers(URL)
    headers["Signature"] += ',signature="AAAA"'
    refute HttpSignature.verified?(request_for(headers:), pem)
  end

  test "garbage is refused rather than raised" do
    refute HttpSignature.verified?(request_for(headers: mastodon_signed_headers(URL).merge("Signature" => 'signature="%%%",headers="host date (request-target)"')), pem)
    refute HttpSignature.verified?(request_for(headers: {}), pem)
  end
end
