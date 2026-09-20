class CreateInstances < ActiveRecord::Migration[8.1]
  def change
    create_table :instances do |t|
      t.string   :domain, null: false
      t.string   :title
      t.string   :client_id
      t.text     :client_secret          # encrypted
      t.string   :redirect_uri
      t.string   :scopes                 # the scope string Mastodon actually granted
      t.jsonb    :oauth_metadata, null: false, default: {}
      t.string   :mastodon_version

      # Cross-instance signals need both: the instance admin's consent, read
      # from `signals=on` in the DNS record, and the operator's approval.
      t.boolean  :signals_opted_in, null: false, default: false
      t.boolean  :signals_approved, null: false, default: false

      # Admission state (see Admission / DnsAllowlist).
      t.string   :status, null: false, default: "unverified"
      t.datetime :verified_at
      t.datetime :verification_checked_at
      t.integer  :consecutive_verification_failures, null: false, default: 0
      t.string   :verification_detail

      t.datetime :last_synced_at
      t.text     :last_sync_error
      t.datetime :last_sync_error_at

      t.timestamps
    end

    add_index :instances, :domain, unique: true
    add_index :instances, :status

    add_check_constraint :instances,
      "status::text IN ('unverified','verified','revoked','blocked')",
      name: "instances_status_check"
  end
end
