# Sync history is a debugging aid: it answers "why didn't this request show
# up?", which nobody asks of a run from last quarter. One row per instance
# every five minutes is about 105,000 a year, so the old end of it is deleted
# rather than kept forever for nobody.
class PurgeSyncRunsJob < ApplicationJob
  queue_as :default

  def perform(older_than: Waterhole::Deployment.sync_history_retention)
    # Unlike a registration request, a run has no dependent records and nothing
    # to anonymise -- these rows are counters and timestamps -- so a plain
    # delete is right, in batches so a first run on a long history does not hold
    # one transaction open across the whole table.
    SyncRun.started_before(older_than.ago).in_batches.delete_all
  end
end
