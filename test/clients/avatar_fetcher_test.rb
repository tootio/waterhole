require "test_helper"

class AvatarFetcherTest < ActiveSupport::TestCase
  URL = "https://files.example/avatars/original/a.png".freeze

  PNG  = "\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR".b
  JPEG = "\xFF\xD8\xFF\xE0\x00\x10JFIF".b
  GIF  = "GIF89a\x01\x00\x01\x00".b
  WEBP = "RIFF\x24\x00\x00\x00WEBPVP8 ".b
  SVG  = %(<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"><script>alert(1)</script></svg>).b

  def stub_image(body, url: URL, content_type: "image/png")
    stub_request(:get, url).to_return(status: 200, body:, headers: { "Content-Type" => content_type })
  end

  test "accepts PNG, JPEG, GIF and WebP by their magic bytes" do
    { PNG => "image/png", JPEG => "image/jpeg", GIF => "image/gif", WEBP => "image/webp" }.each do |bytes, type|
      stub_image(bytes, content_type: "application/octet-stream")

      assert_equal [ bytes, type ], AvatarFetcher.fetch(URL)
    end
  end

  # The header is the server's say-so; only the bytes count.
  test "rejects an SVG, even one served as a PNG" do
    stub_image(SVG, content_type: "image/png")

    assert_raises(AvatarFetcher::Rejected) { AvatarFetcher.fetch(URL) }
  end

  test "rejects anything else that is not a raster image" do
    stub_image("<!doctype html><title>hi</title>", content_type: "text/html")

    assert_raises(AvatarFetcher::Rejected) { AvatarFetcher.fetch(URL) }
  end

  test "rejects a file over the size cap" do
    stub_image(PNG + ("\x00".b * AvatarFetcher::MAX_BYTES))

    assert_raises(AvatarFetcher::Rejected) { AvatarFetcher.fetch(URL) }
  end

  test "fetches only over https" do
    assert_raises(AvatarFetcher::Rejected) { AvatarFetcher.fetch("http://files.example/a.png") }
    assert_raises(AvatarFetcher::Rejected) { AvatarFetcher.fetch("https://user:pass@files.example/a.png") }
    assert_raises(AvatarFetcher::Rejected) { AvatarFetcher.fetch("javascript:alert(1)") }
    assert_raises(AvatarFetcher::Rejected) { AvatarFetcher.fetch("not a url") }
  end

  test "an error status is a rejection" do
    stub_request(:get, URL).to_return(status: 404)

    assert_raises(AvatarFetcher::Rejected) { AvatarFetcher.fetch(URL) }
  end

  test "follows https redirects, relative ones too" do
    stub_request(:get, URL).to_return(status: 302, headers: { "Location" => "https://cdn.example/a.png" })
    stub_request(:get, "https://cdn.example/a.png").to_return(status: 301, headers: { "Location" => "/b.png" })
    stub_image(PNG, url: "https://cdn.example/b.png")

    assert_equal [ PNG, "image/png" ], AvatarFetcher.fetch(URL)
  end

  test "will not follow a redirect to http" do
    stub_request(:get, URL).to_return(status: 302, headers: { "Location" => "http://cdn.example/a.png" })

    assert_raises(AvatarFetcher::Rejected) { AvatarFetcher.fetch(URL) }
  end

  test "gives up after #{AvatarFetcher::MAX_REDIRECTS} redirects" do
    hops = (0..AvatarFetcher::MAX_REDIRECTS + 1).map { "https://cdn.example/#{it}.png" }
    hops.each_cons(2) { |from, to| stub_request(:get, from).to_return(status: 302, headers: { "Location" => to }) }
    stub_image(PNG, url: hops.last)

    assert_raises(AvatarFetcher::Rejected) { AvatarFetcher.fetch(hops.first) }

    # One fewer is fine.
    assert_equal [ PNG, "image/png" ], AvatarFetcher.fetch(hops.second)
  end

  test "a connection failure is a rejection" do
    stub_request(:get, URL).to_timeout

    assert_raises(AvatarFetcher::Rejected) { AvatarFetcher.fetch(URL) }
  end
end
