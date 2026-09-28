require "json"

module DomainLists
  # Throwaway email providers, from disposable-email-domains/disposable-email-domains
  # (CC0). The upstream list changes most days, so RefreshDisposableEmailDomainsJob
  # fetches it daily into the domain lists directory. Until a download has succeeded
  # -- a fresh install, a machine without outbound access -- the copy vendored in
  # lib/data stands in, so throwaway addresses are flagged from the first sync.
  module DisposableEmailDomains
    NAME = "disposable-email-domains"
    SOURCE_URL = "https://raw.githubusercontent.com/disposable-email-domains/disposable-email-domains/main/disposable_email_blocklist.conf"
    VENDORED_PATH = Rails.root.join("lib/data/disposable_email_domains.txt")

    # The list has held thousands of domains for years. Far fewer means the
    # download was truncated or is not the list, and installing it would quietly
    # stop flagging most throwaway addresses.
    MINIMUM_DOMAINS = 1_000

    # A week of failed daily refreshes; surfaced by waterhole:domain_lists:status.
    STALE_AFTER = 7.days

    DOMAIN = /\A[a-z0-9-]+(\.[a-z0-9-]+)+\z/

    @mutex = Mutex.new

    module_function

    def directory = @directory || Waterhole::Deployment.domain_lists_directory

    # Setter for the test suite only: whether this machine happens to have a list
    # downloaded must not change what the tests assert.
    def directory=(path)
      @directory = path && Pathname(path)
      reset!
    end

    # Test seam, shaped like Ip::Databases.stub_directory.
    def stub_directory(path)
      previous = @directory
      self.directory = path
      yield
    ensure
      self.directory = previous
    end

    def path = directory.join("#{NAME}.txt")

    def metadata_path = directory.join("#{NAME}.json")

    def installed? = path.exist?

    # The downloaded list once there is one, the vendored copy until then.
    def source_path = installed? ? path : VENDORED_PATH

    # Exactly this domain on the list; listed_domain also finds subdomains.
    def listed?(domain) = domains.include?(domain)

    # The listed domain an address's domain falls under, or nil: the domain
    # itself, then each parent down to the registrable domain. Throwaway services
    # hand out subdomains (anything.mailinator.com) and the list names only the
    # service; but past the registrable domain every parent is a public suffix
    # (co.uk, or a shared host such as dynv6.net), owned by nobody in particular.
    #
    # Domains are compared in punycode, as the list and EmailCanonicalizer
    # write them; but the suffix list is written in Unicode, and asked in
    # punycode it would mistake a suffix like 公司.cn for a registrable domain.
    def listed_domain(domain)
      domain = EmailCanonicalizer.normalise_domain(domain.to_s.strip)
      return nil if domain.empty?

      listed = domains
      return domain if listed.include?(domain)

      labels = domain.split(".")
      return nil if labels.size <= 2 # no parent that is not a suffix

      registrable = PublicSuffix.domain(unicode_labels(labels).join("."))
      return nil if registrable.nil?

      parents = labels.size - registrable.count(".") - 1
      (1..parents).map { labels.drop(it).join(".") }.find { listed.include?(it) }
    rescue PublicSuffix::Error
      nil
    end

    # Each label in Unicode where it decodes, as written where it does not. A
    # malformed xn-- label (anyone can put one in front of a wildcard throwaway
    # domain) must neither hide the listed parent nor escape as an error: SimpleIDN
    # raises plain RangeError, not only its ConversionError, on some of them.
    def unicode_labels(labels)
      labels.map do |label|
        SimpleIDN.to_unicode(label)
      rescue StandardError
        label
      end
    end

    # Reloaded when the file changes, so a refresh reaches a running worker
    # without a restart. Keyed on more than the mtime, which two installs within
    # one timestamp tick can share. Should the download vanish between the check
    # and the read (a cleared storage volume), the vendored copy stands in.
    def domains
      domains_from(source_path)
    rescue Errno::ENOENT
      domains_from(VENDORED_PATH)
    end

    def domains_from(file)
      stat = file.stat
      key = [ file, stat.mtime, stat.ino, stat.size ]
      @mutex.synchronize do
        if @loaded_from != key
          @domains = read(file).to_set
          @loaded_from = key
        end
        @domains
      end
    end

    def reset! = @mutex.synchronize { @domains = @loaded_from = nil }

    # Both files are already normalised: parse writes the download, and the
    # vendored copy is one.
    def read(file)
      file.readlines(chomp: true).reject { it.empty? || it.start_with?("#") }
    end

    # The upstream format: one domain per line, nothing else. Anything that is
    # not a domain means the download is not the list. An entry in Unicode is
    # still a domain, stored in punycode like the rest.
    def parse(body)
      lines = body.to_s.dup.force_encoding(Encoding::UTF_8).lines(chomp: true).map(&:strip).reject(&:empty?)
      domains = lines.map { EmailCanonicalizer.normalise_domain(it) }.uniq
      invalid = domains.grep_v(DOMAIN)
      raise "#{invalid.size} malformed line(s), e.g. #{invalid.first.inspect}" if invalid.any?
      raise "only #{domains.size} domains; keeping the previous list" if domains.size < MINIMUM_DOMAINS

      domains.sort
    end

    # Written whole and renamed into place, so a reader never sees half a file.
    def write_metadata(values)
      temporary = directory.join("#{NAME}.json.write-#{SecureRandom.hex(4)}")
      temporary.write(values.to_json)
      File.rename(temporary, metadata_path)
    ensure
      FileUtils.rm_f(temporary.to_s) if temporary
    end

    def metadata
      return {} unless metadata_path.exist?

      JSON.parse(metadata_path.read)
    rescue JSON::ParserError
      {}
    end

    def fetched_at
      value = metadata["fetched_at"]
      value && Time.zone.parse(value)
    end

    def stale?
      at = fetched_at
      at.nil? || at < STALE_AFTER.ago
    end
  end
end
