class Current < ActiveSupport::CurrentAttributes
  attribute :session

  delegate :moderator, to: :session, allow_nil: true

  # NOT `instance`: ActiveSupport::CurrentAttributes already defines `.instance`
  # as its own singleton accessor, so `Current.instance` would silently return
  # the Current object rather than the Mastodon instance.
  def self.mastodon_instance = moderator&.instance
end
