# What remains of a purged registration request: Mastodon's account ID and
# nothing else, so SyncInstanceJob never imports the account again while
# Mastodon still lists it as pending. See RegistrationRequest#purge!.
class PurgedRegistration < ApplicationRecord
  belongs_to :instance
end
