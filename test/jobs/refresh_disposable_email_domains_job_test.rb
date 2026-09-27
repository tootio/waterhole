require "test_helper"

class RefreshDisposableEmailDomainsJobTest < ActiveSupport::TestCase
  URL = DomainLists::DisposableEmailDomains::SOURCE_URL

  def list(count = DomainLists::DisposableEmailDomains::MINIMUM_DOMAINS) = (1..count).map { "throwaway#{it}.example" }.join("\n")

  test "downloads, installs, and replaces the vendored copy" do
    Dir.mktmpdir do |dir|
      DomainLists::DisposableEmailDomains.stub_directory(dir) do
        stub_request(:get, URL).to_return(status: 200, body: list)

        RefreshDisposableEmailDomainsJob.perform_now

        assert DomainLists::DisposableEmailDomains.installed?
        assert DomainLists::DisposableEmailDomains.include?("throwaway7.example")
        refute DomainLists::DisposableEmailDomains.include?("mailinator.com")
        refute DomainLists::DisposableEmailDomains.stale?
        assert_equal DomainLists::DisposableEmailDomains::MINIMUM_DOMAINS, DomainLists::DisposableEmailDomains.metadata["domain_count"]
        assert_empty Dir.glob(File.join(dir, "*download*"))
      end
    end
  end

  test "a changed list is applied to the pending queue at once, and only there" do
    Dir.mktmpdir do |dir|
      DomainLists::DisposableEmailDomains.stub_directory(dir) do
        pending = registration_requests(:pending_alpha)
        pending.update!(email: "someone@throwaway7.example")
        resolved = registration_requests(:rejected_alpha)
        resolved.update!(email: "someone@throwaway7.example")
        [ pending, resolved ].each(&:recompute_flags!)
        [ pending, resolved ].each { refute it.reload.flags.exists?(rule: "disposable_email") }

        stub_request(:get, URL).to_return(status: 200, body: list)
        RefreshDisposableEmailDomainsJob.perform_now

        assert pending.reload.flags.exists?(rule: "disposable_email"), "a pending request picks up the new listing"
        refute resolved.reload.flags.exists?(rule: "disposable_email"), "a decided request is left as it was"

        # Dropped from the list again: the flag goes too.
        WebMock.reset!
        stub_request(:get, URL).to_return(status: 200, body: list.sub(/^throwaway7\.example$/, "throwaway0.example"))
        RefreshDisposableEmailDomainsJob.perform_now

        refute pending.reload.flags.exists?(rule: "disposable_email")
      end
    end
  end

  # Unconditional, so nothing depends on noticing the change: a run that died
  # halfway, or a machine that cannot download at all, still settles.
  test "a failed download still reconciles the queue with the list in use" do
    Dir.mktmpdir do |dir|
      DomainLists::DisposableEmailDomains.stub_directory(dir) do
        pending = registration_requests(:pending_alpha)
        pending.update_columns(email_domain: "mailinator.com") # listed in the vendored copy, never recomputed
        stub_request(:get, URL).to_return(status: 503)

        RefreshDisposableEmailDomainsJob.perform_now

        assert pending.reload.flags.exists?(rule: "disposable_email")
      end
    end
  end

  test "the listed domain a flag names is kept current" do
    Dir.mktmpdir do |dir|
      DomainLists::DisposableEmailDomains.stub_directory(dir) do
        pending = registration_requests(:pending_alpha)
        pending.update!(email: "someone@mail.throwaway7.example")
        stub_request(:get, URL).to_return(status: 200, body: list)
        RefreshDisposableEmailDomainsJob.perform_now
        assert_equal "throwaway7.example", pending.reload.flags.find_by(rule: "disposable_email").details["listed"]

        # Now listed itself: still flagged, but no longer "a subdomain of".
        stub_request(:get, URL).to_return(status: 200, body: "#{list}\nmail.throwaway7.example")
        RefreshDisposableEmailDomainsJob.perform_now

        assert_nil pending.reload.flags.find_by(rule: "disposable_email").details["listed"]
      end
    end
  end

  test "an unwritable directory is logged, and the queue is still reconciled" do
    Dir.mktmpdir do |dir|
      blocker = File.join(dir, "not-a-directory")
      File.write(blocker, "")
      DomainLists::DisposableEmailDomains.stub_directory(File.join(blocker, "lists")) do
        registration_requests(:pending_alpha).update_columns(email_domain: "mailinator.com")

        assert_nothing_raised { RefreshDisposableEmailDomainsJob.perform_now }

        assert registration_requests(:pending_alpha).flags.exists?(rule: "disposable_email")
      end
    end
  end

  test "a truncated list keeps the previous one" do
    Dir.mktmpdir do |dir|
      DomainLists::DisposableEmailDomains.stub_directory(dir) do
        stub_request(:get, URL).to_return(status: 200, body: list)
        RefreshDisposableEmailDomainsJob.perform_now
        original = DomainLists::DisposableEmailDomains.path.read

        WebMock.reset!
        stub_request(:get, URL).to_return(status: 200, body: list(10))
        RefreshDisposableEmailDomainsJob.perform_now

        assert_equal original, DomainLists::DisposableEmailDomains.path.read
        assert_match(/only 10 domains/, DomainLists::DisposableEmailDomains.metadata["error"])
      end
    end
  end

  test "something that is not the list is refused, and the vendored copy stays in use" do
    Dir.mktmpdir do |dir|
      DomainLists::DisposableEmailDomains.stub_directory(dir) do
        stub_request(:get, URL).to_return(status: 200, body: "<html>#{list}</html>")

        RefreshDisposableEmailDomainsJob.perform_now

        refute DomainLists::DisposableEmailDomains.installed?
        assert DomainLists::DisposableEmailDomains.include?("mailinator.com")
        assert_match(/malformed/, DomainLists::DisposableEmailDomains.metadata["error"])
      end
    end
  end

  test "an HTTP error is recorded, not raised" do
    Dir.mktmpdir do |dir|
      DomainLists::DisposableEmailDomains.stub_directory(dir) do
        stub_request(:get, URL).to_return(status: 503)

        assert_nothing_raised { RefreshDisposableEmailDomainsJob.perform_now }

        refute DomainLists::DisposableEmailDomains.installed?
        assert_match(/HTTP 503/, DomainLists::DisposableEmailDomains.metadata["error"])
      end
    end
  end
end
