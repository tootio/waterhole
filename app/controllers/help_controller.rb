# Static help pages for signed-in moderators: what a flag rule means, what
# the keyboard shortcuts do, how to write a watchword regexp -- and, public,
# what can get in the way of signing in. Gated by the default moderator
# authentication in ApplicationController -- no opt-in needed here.
#
# Normally full pages, but every link to one is opened by modal_controller.js
# in a <dialog> instead: it fetches the same URL as XHR, and gets back just
# the content, with no layout around it, to drop into the dialog.
class HelpController < ApplicationController
  # Except sign-in help, which is for moderators a sign-in just turned away.
  allow_unauthenticated_access only: :sign_in
  allow_without_consent only: :sign_in

  # A Proc layout returning nil falls back to the default layout -- returning
  # false is what actually disables it.
  layout -> { request.xhr? ? false : "application" }

  def shortcuts
  end

  def regexp
  end

  def sign_in
  end

  def flag
    @flag = Flag.where(registration_request: registration_requests_scope).find(params[:id])
  end
end
