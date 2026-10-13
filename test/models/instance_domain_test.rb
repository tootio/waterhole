require "test_helper"

class InstanceDomainTest < ActiveSupport::TestCase
  test "a pasted URL is reduced to its host" do
    assert_equal "mastodon.example", Instance.normalize_domain(" https://Mastodon.Example/explore ")
    assert_equal "mastodon.example", Instance.normalize_domain("http://mastodon.example/")
    assert_equal "mastodon.example", Instance.normalize_domain("mastodon.example/@admin?x=1#top")
    assert_equal "mastodon.example", Instance.normalize_domain("https://user:pw@mastodon.example")
    assert_equal "mastodon.example", Instance.normalize_domain("mastodon.example")
  end

  test "the default HTTPS port is dropped" do
    assert_equal "mastodon.example", Instance.normalize_domain("https://mastodon.example:443/explore")
    assert_equal "mastodon.example", Instance.normalize_domain("mastodon.example:443")
  end

  test "any other port cannot be reached, so there is no domain" do
    assert_nil Instance.normalize_domain("https://mastodon.example:8443/explore")
    assert_nil Instance.normalize_domain("mastodon.example:80")
  end

  test "input that is not a URL is left for validation to reject" do
    assert_equal "not a domain", Instance.normalize_domain("not a domain")
    assert_not Instance.new(domain: "not a domain").valid?
  end

  test "blank input stays blank" do
    assert_equal "", Instance.normalize_domain(nil)
    assert_equal "", Instance.normalize_domain("  ")
  end
end
