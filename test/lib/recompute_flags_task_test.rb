require "test_helper"
require "rake"

class RecomputeFlagsTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.none?
    Rake::Task["waterhole:recompute_flags"].reenable
  end

  teardown { Rake::Task["waterhole:recompute_flags"].reenable }

  test "pending requests get the flags today's rules give them, decided ones keep theirs" do
    pending  = registration_requests(:pending_alpha)
    rejected = registration_requests(:rejected_alpha)
    # As if flagged by an older rule: stale on both.
    [ pending, rejected ].each { it.flags.create!(rule: "tor_relay", severity: "info") }
    pending.update_columns(invite_request: nil)

    assert_output(/Recomputed the flags of \d+ pending requests\./) { Rake::Task["waterhole:recompute_flags"].invoke }

    assert_equal %w[no_invite_request], pending.reload.flags.pluck(:rule)
    assert_equal 1, pending.flags_count
    assert rejected.reload.flags.exists?(rule: "tor_relay"), "a decided request keeps the flags it was decided on"
  end
end
