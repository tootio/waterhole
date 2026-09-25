# The instance actor's public key, pinned on first sign-in, tells one Mastodon
# install apart from a later one that happens to get the same domain; the proof
# timestamp records when the server last showed it holds the private half.
class AddActorPublicKeyToInstances < ActiveRecord::Migration[8.1]
  def change
    add_column :instances, :actor_public_key, :text
    add_column :instances, :actor_key_pinned_at, :datetime
    add_column :instances, :actor_key_proven_at, :datetime
  end
end
