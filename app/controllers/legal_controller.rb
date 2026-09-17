# The deployment's terms, privacy policy and imprint.
#
# Unauthenticated on purpose, and that matters twice over: an instance admin has
# to READ these before accepting them in DNS, and a moderator whose instance has
# fallen behind on the terms must still be able to reach the very page they are
# being told to act on. `allow_unauthenticated_access` skips both
# require_authentication and require_admitted_instance, which is exactly right
# here.
class LegalController < ApplicationController
  allow_unauthenticated_access
  # The consent page asks moderators to read these first.
  allow_without_consent

  def show
    @document = LegalDocuments.find(params[:slug])
    return head :not_found if @document.nil?

    @example = !@document.published?
  end
end
