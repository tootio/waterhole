# What remains of a purged registration request: only Mastodon's account ID,
# so sync never imports it again while Mastodon still lists it as pending.
# The request itself -- data, notes, flags, decision -- is deleted.
class CreatePurgedRegistrations < ActiveRecord::Migration[8.1]
  def change
    create_table :purged_registrations do |t|
      t.references :instance, null: false, foreign_key: true, index: false
      t.string :mastodon_account_id, null: false
      t.datetime :created_at, null: false
    end
    add_index :purged_registrations, [ :instance_id, :mastodon_account_id ], unique: true,
      name: "index_purged_registrations_on_instance_and_account"
  end
end
