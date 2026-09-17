# Moderators' explicit consent to the processing of their data (see
# ConsentsController). Recorded per version of the privacy policy, so a change
# to it asks again.
class AddConsentToModerators < ActiveRecord::Migration[8.1]
  def change
    add_column :moderators, :consented_at, :datetime
    add_column :moderators, :consented_privacy_digest, :string
  end
end
