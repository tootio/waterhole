# Match keys for signup farms that rotate their IP addresses: see
# ReasonFingerprint, SignupShape and the similar_reason and signup_burst flags.
class AddSignupPatternsToRegistrationRequests < ActiveRecord::Migration[8.1]
  def change
    # No index: matching is by Hamming distance, a scan over a queue this size.
    add_column :registration_requests, :invite_fingerprint, :bigint
    add_column :registration_requests, :signup_shape, :string
    add_index :registration_requests, [ :signup_shape, :signed_up_at ]
    # Set when the account was created through an OAuth app (Mastodon's API)
    # rather than the website's sign-up form. The ID is the instance's own:
    # Mastodon exposes no name or website for it.
    add_column :registration_requests, :created_by_application_id, :string
  end
end
