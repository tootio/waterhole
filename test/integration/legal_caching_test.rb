require "test_helper"

# These documents change a few times a year and are read by every instance
# admin before they accept them in DNS, so a revalidation that ends in 304 is
# most of the traffic this app serves to strangers.
class LegalCachingTest < ActionDispatch::IntegrationTest
  def revalidate(path)
    get path
    assert_response :success
    get path, headers: {
      "HTTP_IF_NONE_MATCH" => response.headers["ETag"],
      "HTTP_IF_MODIFIED_SINCE" => response.headers["Last-Modified"]
    }
  end

  test "an unchanged document revalidates to 304" do
    with_legal_documents do
      revalidate(privacy_path)

      assert_response :not_modified
      assert_empty response.body
    end
  end

  test "the example text is cacheable too, and separately from the real thing" do
    get privacy_path
    example_etag = response.headers["ETag"]

    with_legal_documents do
      get privacy_path

      assert_not_equal example_etag, response.headers["ETag"],
        "the example text and a published document are not the same page"
    end
  end

  test "editing the document ends the cached copy" do
    etag = nil
    with_legal_documents do
      get privacy_path
      etag = response.headers["ETag"]
    end

    with_legal_documents(privacy_policy: "# Privacy\n\nWe changed our minds.\n") do
      get privacy_path, headers: { "HTTP_IF_NONE_MATCH" => etag }

      assert_response :success
      assert_includes response.body, "changed our minds"
    end
  end

  # The badge in the footer is deployment state, not this document's, and it
  # would otherwise sit stale behind an unchanged imprint.
  test "publishing any document ends the cached copy of the others" do
    get imprint_path
    etag = response.headers["ETag"]

    with_legal_documents do
      get imprint_path, headers: { "HTTP_IF_NONE_MATCH" => etag }

      assert_response :success
    end
  end

  # Deliberate. The header carries their handle and a queue badge that moves
  # whenever the queue does, so there is no validator for this page that would
  # still be true a minute later. Rack::ETag cannot stand in either: the CSP
  # nonce is regenerated per request, so no two renderings are byte-identical.
  test "a signed-in moderator always gets a fresh page" do
    sign_in_as moderators(:avery)

    with_legal_documents do
      get privacy_path
      assert_response :success

      get privacy_path, headers: { "HTTP_IF_NONE_MATCH" => response.headers["ETag"] }

      assert_response :success, "never a 304, so never a stale header"
    end
  end

  # The cached body carries the CSP nonce it was rendered with, and a 304's
  # headers replace the stored ones. A 304 that carried a fresh
  # Content-Security-Policy would invalidate the nonces in the very body it just
  # revalidated, and the page would come back without its stylesheets. It does
  # not today only because Rails adds that header to HTML responses, which a 304
  # is not -- worth pinning, because nothing else would notice it changing.
  test "a 304 does not replace the cached page's content security policy" do
    with_legal_documents do
      get privacy_path
      assert_includes response.headers["Content-Security-Policy"].to_s, "nonce-"

      get privacy_path, headers: { "HTTP_IF_NONE_MATCH" => response.headers["ETag"] }

      assert_response :not_modified
      assert_not response.headers.key?("Content-Security-Policy"),
        "the stored header, which matches the stored body's nonce, has to survive"
    end
  end

  # The document is the same for every signed-out reader, so this skips
  # rendering the page rather than rendering it to compare digests.
  test "the signed-out validator is the document itself, not its rendering" do
    with_legal_documents do
      get privacy_path

      assert response.headers["Last-Modified"].present?,
        "a file-backed document has a modification time worth sending"
    end
  end

  test "a 304 still says how long it may be reused for" do
    with_legal_documents do
      revalidate(terms_path)

      assert_response :not_modified
      assert_match(/private/, response.headers["Cache-Control"].to_s,
        "these pages carry a session cookie and a CSRF token; a shared cache must not keep them")
    end
  end
end
