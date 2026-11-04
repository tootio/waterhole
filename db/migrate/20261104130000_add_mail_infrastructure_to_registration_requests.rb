class AddMailInfrastructureToRegistrationRequests < ActiveRecord::Migration[8.1]
  def change
    # The MX hosts of the email domain when the signup was observed. DNS changes,
    # so this is a snapshot: looking again later would describe someone else's
    # mail setup, or none at all once a throwaway domain has gone.
    add_column :registration_requests, :email_mx_hosts, :string, array: true
    # nil means "never looked", which is NOT the same as "looked and found no
    # records". Sync keeps asking for a lookup until this is set.
    add_column :registration_requests, :email_mx_checked_at, :datetime
  end
end
