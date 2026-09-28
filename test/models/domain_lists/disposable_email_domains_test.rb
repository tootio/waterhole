require "test_helper"

class DomainLists::DisposableEmailDomainsTest < ActiveSupport::TestCase
  test "the vendored copy stands in until a list is downloaded" do
    refute DomainLists::DisposableEmailDomains.installed?
    assert_equal DomainLists::DisposableEmailDomains::VENDORED_PATH, DomainLists::DisposableEmailDomains.source_path
    assert DomainLists::DisposableEmailDomains.listed?("mailinator.com")
  end

  test "a listed domain and its subdomains match, down to the registrable domain" do
    assert_equal "mailinator.com", DomainLists::DisposableEmailDomains.listed_domain("mailinator.com")
    assert_equal "mailinator.com", DomainLists::DisposableEmailDomains.listed_domain("a.b.mailinator.com")
    assert_equal "mailinator.co.uk", DomainLists::DisposableEmailDomains.listed_domain("x.mailinator.co.uk")
    assert_nil DomainLists::DisposableEmailDomains.listed_domain("mailinator-fan.org")
    assert_nil DomainLists::DisposableEmailDomains.listed_domain("")
    assert_nil DomainLists::DisposableEmailDomains.listed_domain(nil)
  end

  # dynv6.net is a public suffix: its subdomains belong to different people,
  # so one listed subdomain says nothing about its siblings.
  test "the walk stops at the registrable domain, never climbing into a public suffix" do
    Dir.mktmpdir do |dir|
      DomainLists::DisposableEmailDomains.stub_directory(dir) do
        DomainLists::DisposableEmailDomains.path.write("dynv6.net\nco.uk\n")

        assert_nil DomainLists::DisposableEmailDomains.listed_domain("someone.dynv6.net")
        assert_nil DomainLists::DisposableEmailDomains.listed_domain("example.co.uk")
        assert_equal "dynv6.net", DomainLists::DisposableEmailDomains.listed_domain("dynv6.net"), "an exact match always counts"
      end
    end
  end

  test "internationalised domains match in either form, and a Unicode suffix still stops the walk" do
    Dir.mktmpdir do |dir|
      DomainLists::DisposableEmailDomains.stub_directory(dir) do
        DomainLists::DisposableEmailDomains.path.write("xn--bcher-kva.example\nxn--55qx5d.cn\n")

        assert_equal "xn--bcher-kva.example", DomainLists::DisposableEmailDomains.listed_domain("mail.xn--bcher-kva.example")
        assert_equal "xn--bcher-kva.example", DomainLists::DisposableEmailDomains.listed_domain("mail.bücher.example")
        # 公司.cn is a public suffix: its subdomains belong to different people.
        assert_nil DomainLists::DisposableEmailDomains.listed_domain("a.b.xn--55qx5d.cn")
      end
    end
  end

  # Anyone can put a malformed xn-- label in front of a wildcard throwaway
  # domain; some make SimpleIDN raise a plain RangeError.
  test "a malformed punycode label neither hides the listed parent nor raises" do
    assert_equal "mailinator.com", DomainLists::DisposableEmailDomains.listed_domain("xn--9.mailinator.com")
    assert_equal "mailinator.com", DomainLists::DisposableEmailDomains.listed_domain("a.xn--ib9b.mailinator.com")
    assert_nil DomainLists::DisposableEmailDomains.listed_domain("a.b.xn--ib9b.com")
  end

  test "a download that vanishes mid-read falls back to the vendored copy" do
    original = DomainLists::DisposableEmailDomains.method(:source_path)
    DomainLists::DisposableEmailDomains.define_singleton_method(:source_path) { Pathname("/nonexistent/list.txt") }

    assert_equal "mailinator.com", DomainLists::DisposableEmailDomains.listed_domain("mailinator.com")
  ensure
    DomainLists::DisposableEmailDomains.define_singleton_method(:source_path, original)
  end

  test "a Unicode entry upstream is stored in punycode rather than refusing the list" do
    body = ([ "bücher.example" ] + (1..DomainLists::DisposableEmailDomains::MINIMUM_DOMAINS).map { "t#{it}.example" }).join("\n")

    assert_includes DomainLists::DisposableEmailDomains.parse(body.b), "xn--bcher-kva.example"
  end

  test "a downloaded list replaces the vendored copy, and a changed file is reloaded" do
    Dir.mktmpdir do |dir|
      DomainLists::DisposableEmailDomains.stub_directory(dir) do
        DomainLists::DisposableEmailDomains.path.write("fresh-throwaway.example\n")
        assert DomainLists::DisposableEmailDomains.listed?("fresh-throwaway.example")
        refute DomainLists::DisposableEmailDomains.listed?("mailinator.com")

        DomainLists::DisposableEmailDomains.path.write("newer-throwaway.example\n")
        FileUtils.touch(DomainLists::DisposableEmailDomains.path, mtime: 1.minute.from_now.to_time)
        assert DomainLists::DisposableEmailDomains.listed?("newer-throwaway.example")
      end
    end
  end
end
