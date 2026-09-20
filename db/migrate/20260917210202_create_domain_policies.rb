class CreateDomainPolicies < ActiveRecord::Migration[8.1]
  def change
    create_table :domain_policies do |t|
      t.string  :domain, null: false
      t.string  :kind, null: false
      t.boolean :include_subdomains, null: false, default: false
      t.text    :reason

      t.timestamps
    end

    add_index :domain_policies, :domain, unique: true
    add_index :domain_policies, :kind

    add_check_constraint :domain_policies,
      "kind::text IN ('allowed','blocked')",
      name: "domain_policies_kind_check"
  end
end
