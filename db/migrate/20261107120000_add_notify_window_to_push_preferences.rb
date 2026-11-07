class AddNotifyWindowToPushPreferences < ActiveRecord::Migration[8.1]
  def change
    # Minutes after local midnight, like daily_at. Both nil: around the clock.
    add_column :push_preferences, :notify_from, :integer
    add_column :push_preferences, :notify_until, :integer
  end
end
