class InstancesController < ApplicationController
  # The herds that come down to this waterhole. Every moderator sees the list:
  # a herd's status is what its own DNS record says, which anyone can look up,
  # and whether it takes part in cross-instance signals is reciprocal -- you
  # only see the signal if you contribute to it, so who else is in is not a
  # secret from the people it is shared with.
  def index
    @instances = herds.order(:domain)
    @domain_policies = DomainPolicy.blocked.order(:domain)
  end

  # Every herd has a page; yours is simply the one you can see the plumbing of.
  def show
    @instance = herds.find_by(domain: params[:id].to_s.strip.downcase)
    head :not_found if @instance.nil?
  end

  private

  # Blocked is the exception, and the reason is the one above: a block is the
  # operator's decision about a domain, not something that domain publishes,
  # and a blocked server is not part of anything here. Scoping the lookup as
  # well as the list keeps a blocked domain from being confirmed by URL.
  def herds = Instance.where.not(status: "blocked")
end
