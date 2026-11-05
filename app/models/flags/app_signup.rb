module Flags
  # The account was created through an OAuth app. Plenty of people sign up in an
  # app, so this is context, not suspicion; but signup tools use the API too, and
  # the application ID lets a moderator see several signups sharing one app.
  #
  # This does not say the website's sign-up form was skipped. Mastodon 5.0 records
  # the app for sign-ups through its OAuth flow as well, which use that form, and
  # the admin API does not tell them from POST /api/v1/accounts. It only records
  # the app once it claims a token, so an abandoned OAuth sign-up has no ID, and
  # the ID can arrive after the first sync.
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
