# A moderator's approve/reject vote on a request: advice to the team, not a
# decision. One per moderator and request -- enforced here, so a double click
# cannot slip a second row past the model.
class CreateVotes < ActiveRecord::Migration[8.1]
  def change
    create_table :votes do |t|
      t.references :registration_request, null: false, foreign_key: true, index: false
      t.references :moderator, null: false, foreign_key: true
      t.string :vote, null: false
      t.timestamps
    end
    add_index :votes, [ :registration_request_id, :moderator_id ], unique: true
    add_check_constraint :votes, "vote::text IN ('approve', 'reject')", name: "votes_vote_check"
  end
end
