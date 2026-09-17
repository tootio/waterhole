# Automated triage signals computed at sync time.
#
# Flags are advisory badges that sort and filter the queue. They never decide
# anything: a human still reads the invite_request and presses the button.
module Flags
  Detection = Data.define(:rule, :severity, :details)

  # Order here is the order rules run; it has no bearing on display, which sorts
  # by severity.
  def self.registry
    [
      Flags::NoInviteRequest,
      Flags::ShortInviteRequest,
      Flags::DisposableEmail,
      Flags::SharedIp,
      Flags::DatacenterAsn,
      Flags::Reapplication,
      Flags::KeywordHit,
      Flags::EmailActiveElsewhere,
      Flags::IpActiveElsewhere
    ]
  end

  # Rules that compare against OTHER instances, and so need the other side
  # recomputed when a new signup arrives here. Derived rather than listed twice,
  # so a third such rule cannot be added and silently forgotten.
  def self.cross_instance_rules = registry.select { it.respond_to?(:counterparts) }

  def self.rule_names = registry.map(&:rule_name)
end
