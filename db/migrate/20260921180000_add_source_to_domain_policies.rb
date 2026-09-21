# Where a policy came from: an operator's own rake task, or an automated
# blocklist sync. Sync must never touch a row someone added by hand, so it
# needs a way to tell the two apart. Existing rows default to "manual" -- they
# were all hand-entered before this column existed.
class AddSourceToDomainPolicies < ActiveRecord::Migration[8.1]
  def change
    add_column :domain_policies, :source, :string, null: false, default: "manual"

    add_check_constraint :domain_policies,
      "source::text IN ('manual','iftas_dni')",
      name: "domain_policies_source_check"
  end
end
