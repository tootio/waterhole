class AddTermsAcceptanceToInstances < ActiveRecord::Migration[8.1]
  def up
    # The digest observed in the instance's DNS record at the last authoritative
    # check, plus when it first went stale and when the grace window closes.
    add_column :instances, :accepted_terms_digest, :string
    add_column :instances, :terms_stale_since, :datetime
    add_column :instances, :terms_grace_until, :datetime

    # terms_outdated is deliberately NOT folded into `revoked`: the record is
    # still published, the remedy is different, and telling an admin their record
    # was removed would send them hunting for the wrong problem.
    remove_check_constraint :instances,
      name: "instances_status_check"
    add_check_constraint :instances,
      "status IN ('unverified','verified','terms_outdated','revoked','blocked')",
      name: "instances_status_check"
  end

  def down
    Instance.where(status: "terms_outdated").update_all(status: "verified")

    remove_check_constraint :instances, name: "instances_status_check"
    add_check_constraint :instances,
      "status IN ('unverified','verified','revoked','blocked')",
      name: "instances_status_check"

    remove_column :instances, :terms_grace_until
    remove_column :instances, :terms_stale_since
    remove_column :instances, :accepted_terms_digest
  end
end
