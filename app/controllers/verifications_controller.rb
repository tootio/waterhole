# The "publish this DNS record" page, and its Check again button.
#
# Unauthenticated: an instance admin needs to see the record BEFORE anyone from
# their server can sign in, which is the whole chicken-and-egg this avoids.
class VerificationsController < ApplicationController
  allow_unauthenticated_access

  # Anyone can make this page look up DNS for any domain, and "Check again"
  # also re-verifies inline. Generous enough for an admin waiting on propagation.
  throttle to: 30, within: 1.minute, name: "verification_lookup", only: :show
  throttle to: 10, within: 1.minute, name: "verification_check", only: :create

  before_action :set_domain

  def show
    @admission = Admission.call(@domain) if @domain.present?
    @expected_record = DnsAllowlist.expected_record(@domain) if @domain.present?
  end

  # DNS propagation means this gets pressed more than once.
  #
  # Redirects rather than rendering: Turbo rejects a 200 HTML body for a form
  # submission ("Form responses must redirect to another location"), and
  # post/redirect/get also leaves the admin on a URL they can bookmark and
  # refresh while they wait for propagation.
  def create
    if @domain.present? && Admission.call(@domain).admitted? &&
        (instance = Instance.find_by(domain: @domain))
      VerifyInstanceJob.perform_now(instance)
    end

    redirect_to verification_path(instance_domain: @domain)
  end

  private

  # NOT :domain -- that is a reserved url_for option (it sets the URL's own
  # domain), so verification_path(domain: x) silently drops it and yields
  # "/verification". :instance_domain cannot collide.
  def set_domain
    @domain = Instance.new(domain: params[:instance_id] || params[:instance_domain]).domain
  end
end
