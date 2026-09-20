require "test_helper"

class PurgeSyncRunsJobTest < ActiveSupport::TestCase
  setup { @instance = instances(:alpha) }

  def run_at(started_at, status: "succeeded")
    @instance.sync_runs.create!(status:, started_at:)
  end

  test "runs older than the retention window are deleted" do
    old = run_at(40.days.ago)
    kept = run_at(2.days.ago)

    PurgeSyncRunsJob.perform_now(older_than: 30.days)

    assert_not SyncRun.exists?(old.id)
    assert SyncRun.exists?(kept.id)
  end

  test "a failed run is not kept longer than a successful one" do
    # The instance carries its own last_sync_error, so the row is not the only
    # record that something went wrong.
    failed = run_at(40.days.ago, status: "failed")

    PurgeSyncRunsJob.perform_now(older_than: 30.days)

    assert_not SyncRun.exists?(failed.id)
  end

  test "a run that never finished is still just an old row" do
    stuck = run_at(40.days.ago, status: "running")

    PurgeSyncRunsJob.perform_now(older_than: 30.days)

    assert_not SyncRun.exists?(stuck.id)
  end

  test "every instance is purged, not only one" do
    mine = run_at(40.days.ago)
    theirs = instances(:beta).sync_runs.create!(status: "succeeded", started_at: 40.days.ago)

    PurgeSyncRunsJob.perform_now(older_than: 30.days)

    assert_empty SyncRun.where(id: [ mine.id, theirs.id ])
  end

  test "the window comes from the deployment when none is given" do
    outside = run_at(Waterhole::Deployment.sync_history_retention.ago - 1.day)
    inside  = run_at(Waterhole::Deployment.sync_history_retention.ago + 1.day)

    PurgeSyncRunsJob.perform_now

    assert_not SyncRun.exists?(outside.id)
    assert SyncRun.exists?(inside.id)
  end
end
