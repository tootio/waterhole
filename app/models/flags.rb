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
      Flags::TorRelay,
      Flags::Reapplication,
      Flags::KeywordHit,
      Flags::EmailActiveElsewhere,
      Flags::IpActiveElsewhere,
      Flags::SimilarReason,
      Flags::SignupBurst,
      Flags::AppSignup
    ]
  end

  # Rules whose flags depend on other requests, and so need the other side
  # recomputed when a new signup arrives here: the ones that include
  # Flags::CrossInstanceFlag. A rule is registered by including it -- see
  # there for what happens when that and `counterparts` do not go together.
  def self.cross_instance_rules = registry.select { it < Flags::CrossInstanceFlag }

  def self.rule_names = registry.map(&:rule_name)
end
