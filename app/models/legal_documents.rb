# The deployment's terms of service, privacy policy and imprint, and the digest
# of them that instance admins accept by publishing it in DNS.
#
# The real files are supplied per deployment in Waterhole::Deployment.legal_directory
# (default storage/legal, outside git and the image); the templates in config/legal
# ship with the code. A fresh deployment therefore has no real documents, which
# must degrade honestly rather than either crashing or silently disabling the gate:
#
#   - pages fall back to the template text behind an unmissable banner
#   - `digest` is nil, so `accepted` is omitted from the expected DNS record
#     and the terms gate is simply not active
#   - the operator is told, on the instances page and in `waterhole:herd:policy`
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

      LegalDocuments.cached_digest(path) { Digest::SHA256.hexdigest(self.class.normalise(path.binread)) }
    end

    # What the DNS record carries for this document: enough of the SHA-256 to
    # tell versions apart, short enough to keep the record readable.
    def short_digest = digest&.first(LegalDocuments::SHORT_DIGEST_LENGTH)

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

  SHORT_DIGEST_LENGTH = 10
  # Stands in for a document the operator has not published, keeping every
  # other document in its position.
  UNPUBLISHED = "-"

  # Order matters: it is the order of the segments in accepted.
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
      @digests = nil
    end

    # Pages and the banner ask for digests many times per request; the files
    # change rarely. Keyed on the file's modification time and size, so an
    # edit is picked up on the next call, with no restart.
    def cached_digest(path)
      stat = path.stat
      key = [ path.to_s, stat.mtime, stat.size ]
      @digest_lock ||= Mutex.new
      @digest_lock.synchronize { (@digests ||= {})[key] ||= yield }
    end

    def all = DOCUMENTS

    def find(slug) = DOCUMENTS.find { it.slug == slug.to_s }

    def published = DOCUMENTS.select(&:published?)

    def missing = DOCUMENTS.reject(&:published?)

    def published? = published.any?

    # What a moderator's consent is recorded against; nil while the privacy
    # policy is not published.
    def privacy_digest = find("privacy_policy").short_digest

    # The value that goes into the DNS record as accepted=: one short
    # digest per document, in DOCUMENTS order, joined by ":" --
    #
    #   accepted=1f1d60911e:a3b2c4d5e6:9e8f7a6b5c
    #
    # Per document so that when the value changes, the admin (and the banner
    # moderators see) can be told WHICH document to re-read, not merely that
    # something did.
    #
    # nil when nothing is published -- see the class comment.
    def digest
      return nil if published.empty?

      DOCUMENTS.map { it.short_digest || UNPUBLISHED }.join(":")
    end

    # The published documents whose segment in `accepted` differs from today's.
    # A value in any other shape -- blank, or the single hash earlier versions
    # used -- tells us nothing about individual documents, so all of them.
    def changed_since(accepted)
      segments = accepted.to_s.downcase.split(":")
      return published if segments.size != DOCUMENTS.size

      DOCUMENTS.zip(segments).filter_map do |document, segment|
        document if document.published? && document.short_digest != segment
      end
    end


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

      sanitized = Rails::HTML5::SafeListSanitizer.new.sanitize(html,
        tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES)

      prepare_tables(sanitized).html_safe
    end

    # A table of prose does not fit a phone, so below sm: the stylesheet stacks
    # each row into a card. Two things have to travel with the markup for that
    # to be readable rather than merely narrow:
    #
    #   data-label -- the header row is no longer beside the cells, and "Until
    #     you close your browser" means nothing without "How long it lasts". The
    #     text has to come from the document's own header, so each cell carries
    #     its own and CSS draws it only where the header is hidden.
    #
    #   role -- stacking means display:block, which strips a table of its table
    #     semantics in every browser. Spelling the roles out restores them for
    #     screen readers; at wide widths they simply match what the elements
    #     already imply.
    #
    # Added after sanitising, on our own markup, from text the sanitiser has
    # already been through.
    def prepare_tables(html)
      return html unless html.include?("<table")

      fragment = Nokogiri::HTML5.fragment(html)

      fragment.css("table").each do |table|
        table["role"] = "table"
        table.css("thead, tbody, tfoot").each { it["role"] = "rowgroup" }
        table.css("tr").each { it["role"] = "row" }
        table.css("th").each { it["role"] = "columnheader" }

        headers = table.css("thead tr:first-child th").map { it.text.strip }

        table.css("tbody tr").each do |row|
          row.css("td").each_with_index do |cell, column|
            cell["role"] = "cell"
            cell["data-label"] = headers[column] if headers[column].present?
          end
        end
      end

      fragment.to_html
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
