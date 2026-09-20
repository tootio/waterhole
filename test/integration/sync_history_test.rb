require "test_helper"

class SyncHistoryTest < ActionDispatch::IntegrationTest
  setup do
    @instance = moderators(:avery).instance
    sign_in_as moderators(:avery)
  end

  def run_for(status, started_at: Time.current, **attributes)
    @instance.sync_runs.create!(status:, started_at:, **attributes)
  end

  test "runs are listed newest first" do
    run_for("succeeded", started_at: 2.hours.ago, pages_fetched: 1)
    run_for("failed", started_at: 1.hour.ago, error_message: "the newest one")

    get sync_runs_path

    assert_response :success
    assert_select "tbody tr:first-of-type", /failed/
  end

  test "the status filter narrows the list" do
    run_for("succeeded", started_at: 2.hours.ago)
    run_for("failed", started_at: 1.hour.ago, error_message: "connection refused")

    get sync_runs_path(status: "failed")

    assert_select "tbody tr td", text: "failed", count: 1
    assert_select "tbody tr td", text: "succeeded", count: 0
  end

  # A hand-edited URL or a stale bookmark should show everything rather than
  # silently show nothing.
  test "a status that is not a status is no filter at all" do
    run_for("succeeded")

    get sync_runs_path(status: "sideways")

    assert_select "tbody tr td", text: "succeeded", count: 1
  end

  test "history longer than a page is paginated" do
    (SyncRunsController::PER_PAGE + 5).times { |i| run_for("succeeded", started_at: i.minutes.ago) }

    get sync_runs_path

    assert_select "tbody tr", count: SyncRunsController::PER_PAGE
    assert_select "nav a", text: /Older/

    get sync_runs_path(page: 2)

    assert_select "tbody tr", count: 5
    assert_select "nav a", text: /Newer/
  end

  # Page two of "failed" has to stay page two of failed.
  test "paging keeps the filter" do
    (SyncRunsController::PER_PAGE + 2).times { |i| run_for("failed", started_at: i.minutes.ago) }
    run_for("succeeded", started_at: 1.day.ago)

    get sync_runs_path(status: "failed", page: 2)

    assert_select "tbody tr", count: 2
    assert_select "tbody tr td", text: "succeeded", count: 0
  end

  test "another instance's runs are not listed" do
    instances(:beta).sync_runs.create!(status: "succeeded", started_at: Time.current, error_message: "beta only")
    run_for("succeeded")

    get sync_runs_path

    assert_select "tbody tr", count: 1
    assert_select "body", { text: /beta only/, count: 0 }
  end

  test "an empty filter says so without claiming there is no history" do
    run_for("succeeded")

    get sync_runs_path(status: "failed")

    assert_select "p", /No failed syncs/
  end
end
