require "test_helper"

class LegalDocumentsTest < ActiveSupport::TestCase
  test "no digest when nothing is published" do
    Dir.mktmpdir do |dir|
      LegalDocuments.stub_directory(dir) do
        assert_nil LegalDocuments.digest, "an unconfigured deployment must not invent a digest"
        refute LegalDocuments.published?
        assert_equal 3, LegalDocuments.missing.size
      end
    end
  end

  test "digest changes when a document changes" do
    with_legal_documents do |dir|
      before = LegalDocuments.digest
      File.write(File.join(dir, "imprint.md"), "# Imprint\n\nSomeone else entirely.\n")

      refute_equal before, LegalDocuments.digest
    end
  end

  # An editor silently converting line endings is not a change to the terms, and
  # making it cost every instance a banner and a deadline is exactly the failure
  # the grace period exists to soften.
  test "line endings and trailing blank lines do not change the digest" do
    with_legal_documents(imprint: "# Imprint\n\nOperated by Someone.\n") do |dir|
      before = LegalDocuments.digest

      File.write(File.join(dir, "imprint.md"), "# Imprint\r\n\r\nOperated by Someone.\r\n\n\n\n")
      assert_equal before, LegalDocuments.digest

      File.write(File.join(dir, "imprint.md"), "﻿# Imprint\n\nOperated by Someone.")
      assert_equal before, LegalDocuments.digest, "a BOM is not a change to the terms either"
    end
  end

  test "internal whitespace is significant" do
    with_legal_documents(imprint: "# Imprint\n\n- one\n- two\n") do |dir|
      before = LegalDocuments.digest
      File.write(File.join(dir, "imprint.md"), "# Imprint\n\n-   one\n-   two\n")

      refute_equal before, LegalDocuments.digest,
        "Markdown indentation is semantic, so it must count"
    end
  end

  test "per-document digests identify which document changed" do
    with_legal_documents do |dir|
      before = LegalDocuments.digests
      File.write(File.join(dir, "privacy_policy.md"), "# Privacy\n\nNew text.\n")
      after = LegalDocuments.digests

      changed = after.reject { |slug, hex| before[slug] == hex }.keys
      assert_equal [ "privacy_policy" ], changed
    end
  end

  # The templates ship with the code in config/legal, so the fallback works
  # wherever the operator's own documents live.
  test "documents fall back to the example text so links are never dead" do
    Dir.mktmpdir do |dir|
      LegalDocuments.stub_directory(dir) do
        document = LegalDocuments.find("imprint")

        refute document.published?
        assert_includes document.body, "EXAMPLE TEXT"
        assert_nil document.digest, "example text must not be digested as if it were real"
      end
    end
  end

  test "install_examples copies templates without overwriting real files" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "imprint.md"), "# Mine\n")

      LegalDocuments.stub_directory(dir) do
        installed = LegalDocuments.install_examples

        assert_equal %w[privacy_policy terms_of_service], installed.sort
        assert_equal "# Mine\n", File.read(File.join(dir, "imprint.md")),
          "an existing document must never be overwritten"
      end
    end
  end

  test "rendered markdown is sanitised" do
    html = LegalDocuments.render("# Hi\n\n<script>alert(1)</script>\n\n[ok](https://example.org)")

    refute_includes html, "<script"
    assert_includes html, "<h1"
    assert_includes html, "example.org"
  end

  test "install_examples creates a legal directory outside the tree" do
    Dir.mktmpdir do |root|
      dir = File.join(root, "legal")

      LegalDocuments.stub_directory(dir) do
        assert_equal 3, LegalDocuments.install_examples.size
        assert File.exist?(File.join(dir, "imprint.md"))
      end
    end
  end

  test "the shipped templates never count as published documents" do
    LegalDocuments.stub_directory(LegalDocuments::TEMPLATE_DIRECTORY) do
      refute LegalDocuments.published?
      assert_nil LegalDocuments.digest
    end
  end

  test "operator documents default to storage/legal, outside the templates" do
    ENV.delete("WATERHOLE_LEGAL_DIR")
    assert_equal Rails.root.join("storage/legal"), Waterhole::Deployment.legal_directory
  end
end
