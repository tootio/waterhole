require "test_helper"

class RefreshIpDatabasesJobTest < ActiveSupport::TestCase
  ASN = Ip::Databases::ASN

  setup do
    @body = IpStubs::FIXTURE_DIR.join("origin-asn.mmdb").binread
    @sha  = Digest::SHA256.hexdigest(@body)
  end

  def stub_release(checksum: @sha, body: @body, checksum_status: 200, body_status: 200)
    stub_request(:get, Ip::Databases.checksum_url(ASN))
      .to_return(status: checksum_status, body: "#{checksum}  #{ASN}.mmdb\n")
    stub_request(:get, Ip::Databases.download_url(ASN))
      .to_return(status: body_status, body:)
  end

  test "downloads, verifies the published checksum, and installs" do
    Dir.mktmpdir do |dir|
      Ip::Databases.stub_directory(dir) do
        stub_release

        RefreshIpDatabasesJob.perform_now(names: [ ASN ])

        assert Ip::Databases.installed?(ASN)
        assert_equal @body, Ip::Databases.path_for(ASN).binread
        assert_equal @sha, Ip::Databases.metadata(ASN)["sha256"]
        refute Ip::Databases.stale?(ASN)
      end
    end
  end

  # An 18 MB binary that gets parsed into a reader should never be trusted
  # unverified.
  test "a corrupted download is refused and the existing file survives intact" do
    Dir.mktmpdir do |dir|
      Ip::Databases.stub_directory(dir) do
        stub_release
        RefreshIpDatabasesJob.perform_now(names: [ ASN ])
        original = Ip::Databases.path_for(ASN).binread

        WebMock.reset!
        stub_release(body: "#{@body}tampered")

        RefreshIpDatabasesJob.perform_now(names: [ ASN ])

        assert_equal original, Ip::Databases.path_for(ASN).binread,
          "a checksum mismatch must never replace a good file"
        assert_match(/checksum mismatch/, Ip::Databases.metadata(ASN)["error"])
      end
    end
  end

  # A checksum-correct file whose schema changed would return nil for every
  # lookup, silently, forever.
  test "a file that does not parse as a known database is refused" do
    Dir.mktmpdir do |dir|
      Ip::Databases.stub_directory(dir) do
        junk = "not an mmdb at all"
        stub_release(body: junk, checksum: Digest::SHA256.hexdigest(junk))

        RefreshIpDatabasesJob.perform_now(names: [ ASN ])

        refute Ip::Databases.installed?(ASN)
        assert Ip::Databases.metadata(ASN)["error"].present?
      end
    end
  end

  test "a missing checksum aborts without writing anything" do
    Dir.mktmpdir do |dir|
      Ip::Databases.stub_directory(dir) do
        stub_release(checksum: "not-a-checksum")

        RefreshIpDatabasesJob.perform_now(names: [ ASN ])

        refute Ip::Databases.installed?(ASN)
      end
    end
  end

  test "leaves no temporary files behind on failure" do
    Dir.mktmpdir do |dir|
      Ip::Databases.stub_directory(dir) do
        stub_release(body: "tampered")
        RefreshIpDatabasesJob.perform_now(names: [ ASN ])

        assert_empty Dir.glob(File.join(dir, "*.download*"))
      end
    end
  end
end
