require "test_helper"
require "rake"

class SyncIftasDniBlocklistTaskTest < ActiveSupport::TestCase
  CSV_URL = Blocklists::IftasDni::DEFAULT_CSV_URL

  setup do
    Rails.application.load_tasks if Rake::Task.tasks.none?
    Rake::Task["waterhole:blocklists:sync_iftas_dni"].reenable
  end

  def stub_csv(rows)
    header = "#domain,#severity,#reject_media,#reject_reports,#public_comment,#obfuscate"
    canary_row = %("dni.invalid","suspend","FALSE","FALSE","iftas:canary","TRUE")
    body = ([ header ] + rows + [ canary_row ]).join("\n")
    stub_request(:get, CSV_URL).to_return(status: 200, body:)
  end

  def csv_row(domain) = %("#{domain}","suspend","FALSE","FALSE","iftas:hate-speech","TRUE")

  test "runs the sync and reports the resulting count" do
    stub_csv(Array.new(20) { |i| csv_row("pad#{i}.example") })

    assert_output(/Synced\. 20 domain\(s\) currently blocked via IFTAS DNI\./) do
      Rake::Task["waterhole:blocklists:sync_iftas_dni"].invoke
    end

    assert_equal 20, DomainPolicy.iftas_dni.count
  end
end
