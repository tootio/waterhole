require "test_helper"

# Open Graph / Twitter Card metadata, the head content an unfurler reads
# rather than a browser. These are the links that actually get shared: the
# landing page, /about (how an instance admin is invited to bring their
# herd), and the legal documents an admin reads before accepting them in DNS.
class MetaTagsTest < ActionDispatch::IntegrationTest
  def meta_content(name_or_property)
    assert_select %(meta[property="#{name_or_property}"], meta[name="#{name_or_property}"]) do |elements|
      return elements.first["content"]
    end
    nil
  end

  test "a public page carries a full Open Graph and Twitter Card block" do
    [ new_session_path, verification_path, terms_path ].each do |path|
      get path

      assert meta_content("og:title").present?, "expected og:title on #{path}"
      assert meta_content("og:description").present?, "expected og:description on #{path}"
      assert meta_content("og:image").present?, "expected og:image on #{path}"
      assert meta_content("og:url").present?, "expected og:url on #{path}"
      assert_equal "website", meta_content("og:type")
      assert_equal "Waterhole", meta_content("og:site_name")
      assert_equal "summary_large_image", meta_content("twitter:card")
      assert_equal meta_content("og:title"), meta_content("twitter:title")
      assert_equal meta_content("og:description"), meta_content("twitter:description")
      assert_equal meta_content("og:image"), meta_content("twitter:image")
    end
  end

  test "og:image is an absolute URL built from the deployment's own host" do
    get new_session_path

    assert_match(/\A#{Regexp.escape(Waterhole::Deployment.base_url)}\/og\.png\z/, meta_content("og:image"))
  end

  # A filter or a domain a moderator happened to have open is nobody's
  # business to republish in a link preview.
  test "og:url and the canonical link drop the query string" do
    get verification_path(instance_domain: "mastodon.example")

    assert_equal "#{Waterhole::Deployment.base_url}#{verification_path}", meta_content("og:url")
    assert_select %(link[rel="canonical"][href="#{Waterhole::Deployment.base_url}#{verification_path}"])
  end

  test "the legal page's description names the document, not the homepage" do
    get privacy_path

    assert_equal "Privacy Policy", assert_select("title").first.text.remove(" — Waterhole")
    assert_match(/Privacy Policy/, meta_content("og:description"))
  end

  test "public/og.png exists and is sized 1200×630" do
    path = Rails.root.join("public/og.png")
    assert path.exist?, "public/og.png is missing"

    width, height = File.binread(path, 8, 16).unpack("N2")
    assert_equal 1200, width
    assert_equal 630, height
  end
end
