class AddAccountStateToRegistrationRequests < ActiveRecord::Migration[8.1]
  def up
    # Mastodon's "frozen" state.
    add_column :registration_requests, :disabled, :boolean, default: false, null: false
    # When Mastodon started the clock on deleting an unconfirmed account. Mastodon
    # does not expose it, so it is worked out from what sync saw: see
    # RegistrationRequest#track_confirmation_request.
    add_column :registration_requests, :confirmation_requested_at, :datetime

    # Every row, not only pending ones: sync never revisits the others. Rows that
    # are frozen already would not count as changed on the next sync, so their
    # queue entry is stamped here, the way sync would have, and announced once.
    execute "UPDATE registration_requests SET disabled = TRUE WHERE raw ->> 'disabled' = 'true'"
    execute <<~SQL.squish
      UPDATE registration_requests SET awaiting_since = COALESCE(awaiting_since, NOW())
      WHERE status = 'pending' AND disabled
    SQL
    execute <<~SQL.squish
      UPDATE registration_requests SET confirmation_requested_at = signed_up_at
      WHERE status = 'pending' AND NOT confirmed AND NOT disabled
    SQL
  end

  def down
    remove_column :registration_requests, :confirmation_requested_at
    remove_column :registration_requests, :disabled
  end
end
