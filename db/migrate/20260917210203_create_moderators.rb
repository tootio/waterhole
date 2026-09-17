class CreateModerators < ActiveRecord::Migration[8.1]
  def change
    create_table :moderators do |t|
      t.references :instance, null: false, foreign_key: true
      t.string   :mastodon_account_id, null: false
      t.string   :username, null: false
      t.string   :display_name
      t.string   :avatar_url
      t.string   :profile_url
      t.string   :role_name
      t.text     :access_token          # encrypted, non-deterministic
      t.string   :token_scopes
      t.datetime :token_invalidated_at  # non-null means the token is known-dead
      t.datetime :last_authenticated_at

      t.timestamps
    end

    add_index :moderators, [ :instance_id, :mastodon_account_id ], unique: true
  end
end
