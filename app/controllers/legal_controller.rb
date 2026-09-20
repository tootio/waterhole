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

    # Signed out, this page renders nothing that varies by viewer: it is a pure
    # function of the document's bytes and the deployment's own identity, and
    # both are in the ETag. These documents change a few times a year and every
    # instance admin reads them before accepting them in DNS, so revalidating to
    # a 304 -- without rendering the page at all -- beats resending them.
    #
    # LegalDocuments.digest is in there for the footer's "no legal documents
    # published" badge, which is deployment state rather than this document's.
    #
    # Signed in, no validator: the header carries the moderator's handle and a
    # queue badge that moves whenever the queue does, and nothing here could
    # tell when either changed. They simply get the page.
    return if signed_in?

    fresh_when(
      etag: [ @document.cache_key, LegalDocuments.digest,
              Waterhole::Deployment.host, Waterhole::Deployment.source_url ],
      last_modified: @document.source_path.exist? ? @document.source_path.mtime : nil
    )
  end
end
