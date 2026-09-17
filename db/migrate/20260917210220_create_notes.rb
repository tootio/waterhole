class CreateNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :notes do |t|
      t.references :registration_request, null: false, foreign_key: true
      t.references :moderator, null: false, foreign_key: true
      # Threading is capped at one level (root + replies); enforced in the model.
      t.references :parent, foreign_key: { to_table: :notes }
      t.text     :body, null: false
      t.datetime :edited_at

      t.timestamps
    end

    add_index :notes, [ :registration_request_id, :created_at ]
  end
end
