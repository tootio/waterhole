# A copy of the moderator's avatar, checked to be a raster image and served
# from our own origin, so the content security policy never has to allow
# images from a moderator's media host (see Mastodon::Avatar). A table of its
# own so the bytes are not loaded with the moderator on every request.
class CreateModeratorAvatars < ActiveRecord::Migration[8.1]
  def change
    create_table :moderator_avatars do |t|
      t.references :moderator, null: false, foreign_key: true, index: { unique: true }
      t.binary :image, null: false
      t.string :content_type, null: false
      t.string :source_url, null: false
      t.timestamps
    end
  end
end
