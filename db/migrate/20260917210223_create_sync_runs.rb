class CreateSyncRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_runs do |t|
      t.references :instance, null: false, foreign_key: true
      t.string   :status, null: false, default: "running"
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.integer  :pages_fetched, null: false, default: 0
      t.integer  :records_seen, null: false, default: 0
      t.integer  :records_created, null: false, default: 0
      t.integer  :records_updated, null: false, default: 0
      t.integer  :records_resolved, null: false, default: 0
      t.text     :error_message

      t.timestamps
    end

    add_index :sync_runs, [ :instance_id, :started_at ]
    add_check_constraint :sync_runs, "status IN ('running','succeeded','failed')",
      name: "sync_runs_status_check"
  end
end
