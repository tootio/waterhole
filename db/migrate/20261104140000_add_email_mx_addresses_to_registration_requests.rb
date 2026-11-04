class AddEmailMxAddressesToRegistrationRequests < ActiveRecord::Migration[8.1]
  def change
    # Where the MX hosts pointed when the signup was observed. A snapshot, like
    # email_mx_hosts: see that column's migration.
    add_column :registration_requests, :email_mx_addresses, :string, array: true
  end
end
