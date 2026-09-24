# A herd's canned emails to applicants, opened in the moderator's own mail
# client. Shared by the instance's moderators, like watchwords.
class CreateEmailTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :email_templates do |t|
      t.references :instance, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.string :subject
      t.text :body, null: false
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    add_index :email_templates, [ :instance_id, :name ], unique: true
  end
end
