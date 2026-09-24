require "test_helper"
require "fugit"

class ScheduleInstanceSyncsJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def sync_jobs = enqueued_jobs.select { it["job_class"] == "SyncInstanceJob" }

  test "enqueues one sync per syncable instance" do
    ScheduleInstanceSyncsJob.perform_now

    assert_equal Instance.syncable.count, sync_jobs.size
    assert_not_includes sync_jobs.map { it["arguments"].to_s }.join, instances(:unverified).domain
  end

  test "spreads the syncs over the interval instead of starting them together" do
    ScheduleInstanceSyncsJob.perform_now

    times = sync_jobs.map { Time.zone.parse(it["scheduled_at"]) }
    assert_equal sync_jobs.size, times.size, "every sync is scheduled, none run immediately"
    assert times.uniq.size > 1, "offsets differ between instances"
    assert times.all? { it < ScheduleInstanceSyncsJob::INTERVAL.from_now }, "and stay inside the interval"
  end

  test "an instance's offset depends only on its id" do
    instance = instances(:alpha)
    offset = ScheduleInstanceSyncsJob.offset_for(instance)

    assert_equal offset, ScheduleInstanceSyncsJob.offset_for(Instance.find(instance.id))
    assert_operator offset, :>=, 0
    assert_operator offset, :<, ScheduleInstanceSyncsJob::INTERVAL
  end

  test "consecutive ids land far apart" do
    offsets = (1..5).map { |id| ScheduleInstanceSyncsJob.offset_for(Instance.new(id:)).to_i }.sort
    gaps = offsets.each_cons(2).map { |a, b| b - a }

    assert_operator gaps.min, :>=, 30, "five instances must not cluster: #{offsets}"
  end

  test "recurring.yml schedules it on the same interval the offsets are spread over" do
    # The file has no `test:` entry, so read the production one directly.
    config = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/recurring.yml"))
    task = config.fetch("production").fetch("sync_instances")
    cron = Fugit.parse(task["schedule"])

    assert_equal "ScheduleInstanceSyncsJob", task["class"]
    assert_equal 0, ScheduleInstanceSyncsJob::INTERVAL.to_i % 60, "must be whole minutes to be scheduled"
    assert_kind_of Fugit::Cron, cron, "#{task['schedule'].inspect} must parse as a cron"
    first = cron.next_time
    assert_equal ScheduleInstanceSyncsJob::INTERVAL, cron.next_time(first).to_t - first.to_t
  end
end
