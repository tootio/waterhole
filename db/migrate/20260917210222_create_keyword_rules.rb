class CreateKeywordRules < ActiveRecord::Migration[8.1]
  def change
    create_table :keyword_rules do |t|
      t.references :instance, null: false, foreign_key: true
      t.string  :pattern, null: false
      t.string  :match_type, null: false, default: "word"
      t.integer :severity, null: false, default: 1
      t.boolean :enabled, null: false, default: true
      t.string  :description

      t.timestamps
    end

    add_index :keyword_rules, :enabled
    add_check_constraint :keyword_rules,
      "match_type IN ('substring','word','regex')",
      name: "keyword_rules_match_type_check"
  end
end
