# The deployment's terms of service, privacy policy and imprint, and the SHA-256
# digest of them that instance admins accept by publishing it in DNS.
#
# The real files are supplied per deployment in Waterhole::Deployment.legal_directory
# (default storage/legal, outside git and the image); the templates in config/legal
# ship with the code. A fresh deployment therefore has no real documents, which
# must degrade honestly rather than either crashing or silently disabling the gate:
#
#   - pages fall back to the template text behind an unmissable banner
#   - `digest` is nil, so `accepted_tos` is omitted from the expected DNS record
#     and the terms gate is simply not active
#   - the operator is told, on the instances page and in `waterhole:policy`
class LegalDocuments
  # Templates ship with the code and are never digested; the real documents are
  # the operator's and live in Waterhole::Deployment.legal_directory.
  TEMPLATE_DIRECTORY = Rails.root.join("config/legal")

  Document = Data.define(:slug, :title, :description) do
    def path         = LegalDocuments.directory.join("#{slug}.md")
    def template_path = TEMPLATE_DIRECTORY.join("#{slug}.md")

    # True once the operator has written their own text. Pointing
    # WATERHOLE_LEGAL_DIR at config/legal must not turn the shipped templates
    # into terms that instances are asked to accept.
    def published? = path.exist? && path.expand_path != template_path.expand_path

    # Falls back to the template so the footer links are never dead.
    def source_path = published? ? path : template_path

    def body = source_path.exist? ? source_path.read : ""

    # Line endings and trailing blank lines are normalised before digesting;
    # nothing else is. The only consequence of a digest change is that every
    # moderation team on every instance gets a banner and a deadline, and an
    # editor silently converting CRLF or adding a trailing newline is not a
    # change to the terms. Internal whitespace IS significant -- Markdown list
    # indentation and fenced code are semantic -- so it is left alone.
    def digest
      return nil unless published?

      Digest::SHA256.hexdigest(self.class.normalise(path.binread))
    end

    def self.normalise(bytes)
      bytes.dup.force_encoding("UTF-8")
           .delete_prefix("\ufeff")
           .gsub("\r\n", "\n").tr("\r", "\n")
           .sub(/\n*\z/, "\n")
    end

    # Data instances are frozen, so the render cache lives on the class.
    def html = LegalDocuments.html_for(self)

    # Identifies the exact bytes being served, whether real or example text.
    def cache_key = digest || "example:#{Digest::SHA256.hexdigest(normalised_body)}"

    def normalised_body = self.class.normalise(body)
  end

  DOCUMENTS = [
    Document.new(slug: "terms_of_service", title: "Terms of Service",
      description: "What this service does, and the rules for using it."),
    Document.new(slug: "privacy_policy", title: "Privacy Policy",
      description: "What personal data is processed, and why."),
    Document.new(slug: "imprint", title: "Imprint",
      description: "Who operates this deployment.")
  ].freeze

  class << self
    def directory = @directory || Waterhole::Deployment.legal_directory

    # Setter for the test suite only. Whether an operator happens to have
    # installed their documents on this machine must not change what the tests
    # assert; see test_helper.rb.
    def directory=(path)
      @directory = path && Pathname(path)
      reset_cache
    end

    # Test seam, shaped like DnsAllowlist.stub_resolver: lets a test point the
    # whole subsystem at a tmpdir with real files, so digests and the
    # example-fallback are exercised rather than mocked.
    def stub_directory(path)
      previous, @directory = @directory, Pathname(path)
      reset_cache
      yield
    ensure
      @directory = previous
      reset_cache
    end

    def reset_cache
      @rendered = nil
    end

    def all = DOCUMENTS

    def find(slug) = DOCUMENTS.find { it.slug == slug.to_s }

    def published = DOCUMENTS.select(&:published?)

    def missing = DOCUMENTS.reject(&:published?)

    def published? = published.any?

    # The value that goes into the DNS record as accepted_tos.
    #
    # Built from per-document digests sorted by slug, so it does not depend on
    # the declaration order above, and so `digests` can tell the admin WHICH
    # document changed rather than only that something did.
    #
    # nil when nothing is published -- see the class comment.
    def digest
      return nil if published.empty?

      lines = published.sort_by(&:slug).map { "#{it.slug}:#{it.digest}\n" }
      Digest::SHA256.hexdigest(lines.join)
    end

    def digests = published.to_h { [ it.slug, it.digest ] }

    ALLOWED_TAGS = %w[p h1 h2 h3 h4 h5 h6 ul ol li a strong em blockquote code pre
                      hr br table thead tbody tr th td].freeze
    ALLOWED_ATTRIBUTES = %w[href id].freeze

    # Memoised per document digest, so editing a document invalidates its HTML
    # with no restart and no sweeper.
    def html_for(document)
      key = [ document.slug, document.cache_key ]
      @render_lock ||= Mutex.new
      @rendered ||= {}

      @render_lock.synchronize { @rendered[key] ||= render(document.body) }
    end

    def render(markdown)
      html = Kramdown::Document.new(markdown.to_s, input: "kramdown",
        html_to_native: false, auto_ids: true, entity_output: :as_char).to_html

      Rails::HTML5::SafeListSanitizer.new.sanitize(html,
        tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES).html_safe
    end

    # Copies any template that has no real file yet.
    def install_examples
      directory.mkpath
      DOCUMENTS.reject(&:published?).filter_map do |document|
        next unless document.template_path.exist?

        FileUtils.cp(document.template_path, document.path)
        document.slug
      end
    end
  end
end
