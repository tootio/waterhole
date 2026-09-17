class CreateRegistrationRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :registration_requests do |t|
      t.references :instance, null: false, foreign_key: true

      # Mastodon's snowflake, a DECIMAL STRING. Used for keys and API paths only --
      # never for ordering (lexicographic order breaks across digit lengths).
      t.string   :mastodon_account_id, null: false

      t.string   :username, null: false
      t.string   :display_name
      t.text     :bio
      t.string   :avatar_url
      t.string   :account_url
      t.string   :locale
      t.boolean  :confirmed, null: false, default: false
      t.boolean  :approved, null: false, default: false

      t.string   :email                 # encrypted, deterministic
      t.string   :email_domain          # plaintext: needed for disposable-domain flags
      t.string   :canonical_email_hash  # HMAC-SHA256, the cross-instance match key
      t.inet     :ip

      # The "why do you want to join?" answer. The whole point of the app; never truncate.
      t.text     :invite_request

      t.datetime :signed_up_at, null: false   # Mastodon's created_at; THE sort key
      t.string   :status, null: false, default: "pending"

      t.references :claimed_by, foreign_key: { to_table: :moderators }
      t.datetime :claimed_at

      t.integer  :notes_count, null: false, default: 0
      t.integer  :flags_count, null: false, default: 0
      t.integer  :max_flag_severity, null: false, default: 0

      t.jsonb    :raw, null: false, default: {}
      t.datetime :last_seen_in_queue_at
      t.datetime :resolved_at

      t.timestamps
    end

    # The idempotency key for re-sync.
    add_index :registration_requests, [ :instance_id, :mastodon_account_id ],
      unique: true, name: "index_registration_requests_on_instance_and_account"

    # The default queue ordering.
    add_index :registration_requests, [ :instance_id, :status, :signed_up_at ],
      name: "index_registration_requests_on_instance_status_signed_up"

    add_index :registration_requests, :email_domain
    add_index :registration_requests, :ip
    add_index :registration_requests, :canonical_email_hash

    # expired: Mastodon deleted the account because its email stayed unconfirmed
    # for a week. That 404 looks like a rejection, but must not be recorded as one.
    add_check_constraint :registration_requests,
      "status IN ('pending','approved','rejected','approved_elsewhere','rejected_elsewhere','expired')",
      name: "registration_requests_status_check"
  end
end
