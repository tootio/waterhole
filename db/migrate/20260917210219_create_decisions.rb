class CreateDecisions < ActiveRecord::Migration[8.1]
  def change
    create_table :decisions do |t|
      t.references :registration_request, null: false, foreign_key: true
      t.references :moderator, null: false, foreign_key: true

      t.string   :action, null: false   # approve | reject
      t.string   :state,  null: false, default: "pending"
      t.integer  :attempts, null: false, default: 0
      t.text     :error_message
      t.jsonb    :response, null: false, default: {}
      t.datetime :performed_at

      t.timestamps
    end

    # One live decision per request. Also the double-submit guard.
    add_index :decisions, :registration_request_id, unique: true,
      name: "index_decisions_on_registration_request_unique"

    add_check_constraint :decisions, "action::text IN ('approve','reject')",
      name: "decisions_action_check"
    add_check_constraint :decisions,
      "state::text IN ('pending','succeeded','failed','conflict')",
      name: "decisions_state_check"
  end
end
