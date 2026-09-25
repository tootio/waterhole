# The moderator's avatar, copied from their Mastodon server by
# FetchModeratorAvatarJob and served by AvatarsController. Only ever bytes that
# AvatarFetcher recognised as a raster image.
class Moderator::Avatar < ApplicationRecord
  belongs_to :moderator
end
