# Static help pages for signed-in moderators: what a flag rule means, and
# what the keyboard shortcuts do. Gated by the default moderator
# authentication in ApplicationController -- no opt-in needed here.
#
# Normally full pages, but every link to one is opened by modal_controller.js
# in a <dialog> instead: it fetches the same URL as XHR, and gets back just
# the content, with no layout around it, to drop into the dialog.
class HelpController < ApplicationController
  # A Proc layout returning nil falls back to the default layout -- returning
  # false is what actually disables it.
  layout -> { request.xhr? ? false : "application" }

  def shortcuts
  end

  def flag
    @flag = Flag.where(registration_request: registration_requests_scope).find(params[:id])
  end
end
