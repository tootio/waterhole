# Optional push notifications to moderators. The preference is one row per
# moderator and every browser they enable is a subscription, because a moderator
# wants the same news on each device. new_checked_at and forgotten_checked_at are
# how far notifications have got, so a request is announced once without a table
# of who has been told what.
class CreatePushNotifications < ActiveRecord::Migration[8.1]
  def up
    add_column :registration_requests, :awaiting_since, :datetime
    add_column :registration_requests, :pending_since, :datetime
    # signed_up_at understates the wait of anyone who confirmed late, but nothing
    # recorded when they did. Nobody has opted in yet, so this announces nothing.
    execute <<~SQL.squish
      UPDATE registration_requests SET awaiting_since = signed_up_at
      WHERE status = 'pending' AND confirmed
    SQL
    execute "UPDATE registration_requests SET pending_since = created_at WHERE status = 'pending'"

    create_table :push_preferences do |t|
      t.references :moderator, null: false, foreign_key: true, index: { unique: true }
      t.string :new_frequency, null: false, default: "hourly"
      t.string :new_scope, null: false, default: "awaiting"
      t.integer :forgotten_after_days
      t.string :forgotten_scope, null: false, default: "awaiting"
      # Minutes after midnight in time_zone.
      t.integer :daily_at, null: false, default: 7 * 60
      t.string :time_zone, null: false, default: "UTC"
      t.datetime :new_checked_at, null: false
      t.datetime :forgotten_checked_at, null: false
      # How far along the requests' own timeline reminders have got.
      t.datetime :forgotten_through
      # Moving daily_at must not bring today's notification round again.
      t.datetime :daily_held_until
      t.timestamps
    end

    create_table :push_subscriptions do |t|
      t.references :moderator, null: false, foreign_key: true, index: false
      t.string :endpoint, null: false
      t.string :p256dh, null: false
      t.string :auth, null: false
      t.timestamps
      # Not on the endpoint alone: one browser may serve one person on two instances.
      t.index %i[moderator_id endpoint], unique: true
    end
  end

  def down
    drop_table :push_subscriptions
    drop_table :push_preferences
    remove_column :registration_requests, :pending_since
    remove_column :registration_requests, :awaiting_since
  end
end
