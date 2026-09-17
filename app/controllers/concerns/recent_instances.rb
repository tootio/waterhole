# The instances this *browser* has signed in to, most recent first.
#
# The sign-in page used to list every verified instance, which told any
# anonymous visitor exactly who moderates with this Waterhole. What that list
# was actually for is a returning moderator skipping the typing, and a per-
# browser memory gives them that without disclosing anyone else.
#
# Signed rather than encrypted: the domains are the browser owner's own
# history, so hiding them from that owner buys nothing, but a forged cookie
# must not be able to plant arbitrary text on the page.
module RecentInstances
  extend ActiveSupport::Concern

  COOKIE = :recent_instances
  LIMIT = 5
  # Rewritten on every sign-in, so this is 90 days since this browser last
  # used *any* instance -- an abandoned browser forgets on its own.
  TTL = 90.days

  included do
    helper_method :recent_instance_domains
  end

  private

  def recent_instance_domains
    Array(cookies.signed[COOKIE]).grep(String).first(LIMIT)
  end

  def remember_recent_instance(domain)
    write_recent_instances([ domain, *recent_instance_domains ].uniq.first(LIMIT))
  end

  def forget_recent_instance(domain)
    write_recent_instances(recent_instance_domains - [ domain ])
  end

  def write_recent_instances(domains)
    if domains.empty?
      cookies.delete(COOKIE)
    else
      cookies.signed[COOKIE] = { value: domains, expires: TTL, httponly: true, same_site: :lax }
    end
  end
end
