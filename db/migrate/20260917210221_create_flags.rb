class CreateFlags < ActiveRecord::Migration[8.1]
  def change
    create_table :flags do |t|
      t.references :registration_request, null: false, foreign_key: true
      t.string  :rule, null: false
      t.integer :severity, null: false, default: 0
      t.jsonb   :details, null: false, default: {}

      t.timestamps
    end

    # Makes recompute an idempotent upsert rather than a duplicate-generator.
    add_index :flags, [ :registration_request_id, :rule ], unique: true,
      name: "index_flags_on_registration_request_and_rule"
    add_index :flags, :rule
  end
end
