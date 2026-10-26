# Hourly signup counts per instance, kept after the requests they count are
# purged: see RollUpRegistrationStatsJob. purged_registration_stats holds the
# same counters for requests purged while their hour is still being recounted.
class CreateRegistrationStats < ActiveRecord::Migration[8.1]
  COUNTERS = %i[signups pending approved rejected approved_elsewhere rejected_elsewhere expired flagged signalled].freeze

  def change
    create_table :registration_stats do |t|
      t.references :instance, null: false, index: false, foreign_key: true
      t.datetime :hour, null: false
      COUNTERS.each { t.integer it, null: false, default: 0 }
      t.timestamps
    end
    add_index :registration_stats, %i[instance_id hour], unique: true

    create_table :purged_registration_stats do |t|
      t.references :instance, null: false, index: false, foreign_key: true
      t.datetime :hour, null: false
      COUNTERS.each { t.integer it, null: false, default: 0 }
    end
    add_index :purged_registration_stats, %i[instance_id hour], unique: true
  end
end
