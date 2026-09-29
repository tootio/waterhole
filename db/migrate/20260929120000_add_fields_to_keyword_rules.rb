# Which of the applicant's texts a watchword is checked against. Existing
# watchwords keep checking all four, as they did before.
class AddFieldsToKeywordRules < ActiveRecord::Migration[8.1]
  def change
    add_column :keyword_rules, :fields, :string, array: true, null: false,
      default: %w[invite_request bio display_name username]
  end
end
