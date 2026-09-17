module Flags
  # The account was created through an OAuth app -- Mastodon's API -- rather
  # than the website's sign-up form. Plenty of people sign up in an app, so
  # this is context, not suspicion; but signup tools use the API too, and the
  # application ID lets a moderator see several signups sharing one app.
  #
  # Mastodon exposes only the instance's own ID for the app, not its name or
  # website, so this cannot be compared across instances.
  class AppSignup < Rule
    def call
      return nil if request.created_by_application_id.blank?

      detect(:info, application_id: request.created_by_application_id)
    end
  end
end
