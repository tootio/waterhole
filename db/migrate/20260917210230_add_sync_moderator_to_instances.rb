class AddSyncModeratorToInstances < ActiveRecord::Migration[8.1]
  # Separate migration because instances <-> moderators is a cycle: a moderator
  # belongs to an instance, and an instance borrows one moderator's token for
  # background sync (jobs have no logged-in user).
  def change
    add_reference :instances, :sync_moderator,
      foreign_key: { to_table: :moderators }, null: true
  end
end
