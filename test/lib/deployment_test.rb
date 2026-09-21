require "test_helper"

class DeploymentTest < ActiveSupport::TestCase
  setup do
    @saved_version = ENV["WATERHOLE_VERSION"]
    ENV.delete("WATERHOLE_VERSION")
    Waterhole::Deployment.reset_version_cache
  end

  teardown do
    ENV.delete("WATERHOLE_VERSION")
    ENV["WATERHOLE_VERSION"] = @saved_version if @saved_version
    Waterhole::Deployment.reset_version_cache
  end

  def with_git(tag: nil, branch: nil, sha: nil, dirty: false)
    orig_tag = Waterhole::Deployment.method(:git_tag)
    orig_branch = Waterhole::Deployment.method(:git_branch)
    orig_sha = Waterhole::Deployment.method(:git_sha)
    orig_dirty = Waterhole::Deployment.method(:git_dirty?)

    Waterhole::Deployment.define_singleton_method(:git_tag) { tag }
    Waterhole::Deployment.define_singleton_method(:git_branch) { branch }
    Waterhole::Deployment.define_singleton_method(:git_sha) { sha }
    Waterhole::Deployment.define_singleton_method(:git_dirty?) { dirty }

    yield
  ensure
    Waterhole::Deployment.define_singleton_method(:git_tag, orig_tag)
    Waterhole::Deployment.define_singleton_method(:git_branch, orig_branch)
    Waterhole::Deployment.define_singleton_method(:git_sha, orig_sha)
    Waterhole::Deployment.define_singleton_method(:git_dirty?, orig_dirty)
  end

  def as_production
    previous = Rails.env
    Rails.env = "production"
    yield
  ensure
    Rails.env = previous
  end

  test "version returns WATERHOLE_VERSION when set" do
    ENV["WATERHOLE_VERSION"] = "v2.0.0"
    assert_equal "v2.0.0", Waterhole::Deployment.version
  end

  test "version returns tag name when on a tag" do
    with_git(tag: "v1.2.3", dirty: false) do
      assert_equal "v1.2.3", Waterhole::Deployment.version
    end
  end

  test "version appends -dev to tag when working tree is dirty" do
    with_git(tag: "v1.2.3", dirty: true) do
      assert_equal "v1.2.3-dev", Waterhole::Deployment.version
    end
  end

  test "version returns branch and commit sha when on a branch without a tag" do
    with_git(branch: "main", sha: "1927964", dirty: false) do
      assert_equal "main-1927964", Waterhole::Deployment.version
    end
  end

  test "version appends -dev to branch and commit sha when working tree is dirty" do
    with_git(branch: "feature/testing", sha: "abcdef0", dirty: true) do
      assert_equal "feature/testing-abcdef0-dev", Waterhole::Deployment.version
    end
  end

  test "version returns commit sha when on detached HEAD without branch or tag" do
    with_git(sha: "1927964", dirty: false) do
      assert_equal "1927964", Waterhole::Deployment.version
    end
  end

  test "version returns commit sha with -dev when on detached HEAD and dirty" do
    with_git(sha: "1927964", dirty: true) do
      assert_equal "1927964-dev", Waterhole::Deployment.version
    end
  end

  test "version falls back to dev when git information is completely unavailable" do
    with_git(dirty: false) do
      assert_equal "dev", Waterhole::Deployment.version
    end
  end

  test "version is memoized in production environment" do
    as_production do
      calls = 0
      orig_detect = Waterhole::Deployment.method(:detect_version)
      Waterhole::Deployment.define_singleton_method(:detect_version) do
        calls += 1
        "memoized-v1"
      end

      begin
        assert_equal "memoized-v1", Waterhole::Deployment.version
        assert_equal "memoized-v1", Waterhole::Deployment.version
        assert_equal 1, calls
      ensure
        Waterhole::Deployment.define_singleton_method(:detect_version, orig_detect)
      end
    end
  end

  test "iftas_dni_sync_enabled? defaults to false" do
    ENV.delete("WATERHOLE_IFTAS_DNI_SYNC")
    assert_not Waterhole::Deployment.iftas_dni_sync_enabled?
  end

  test "iftas_dni_sync_enabled? reads WATERHOLE_IFTAS_DNI_SYNC as a boolean" do
    ENV["WATERHOLE_IFTAS_DNI_SYNC"] = "true"
    assert Waterhole::Deployment.iftas_dni_sync_enabled?
  ensure
    ENV.delete("WATERHOLE_IFTAS_DNI_SYNC")
  end

  test "iftas_dni_url defaults to the published sheet" do
    ENV.delete("WATERHOLE_IFTAS_DNI_URL")
    assert_equal Blocklists::IftasDni::DEFAULT_CSV_URL, Waterhole::Deployment.iftas_dni_url
  end

  test "iftas_dni_url can be overridden" do
    ENV["WATERHOLE_IFTAS_DNI_URL"] = "https://example.org/dni.csv"
    assert_equal "https://example.org/dni.csv", Waterhole::Deployment.iftas_dni_url
  ensure
    ENV.delete("WATERHOLE_IFTAS_DNI_URL")
  end
end
