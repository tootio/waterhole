# Re-verifies one instance's DNS record: that it still authorises this
# deployment, and that it accepts the legal documents currently in force.
#
# The three-way outcome from DnsAllowlist is the point. A resolver failure says
# nothing about what is published, so it must never count towards revocation --
# otherwise a DNS blip on Waterhole's side signs out an entire moderation team
# for a reason they cannot fix.
class VerifyInstanceJob < ApplicationJob
  queue_as :default

  FAILURES_BEFORE_REVOCATION = Instances::ApplyVerification::FAILURES_BEFORE_REVOCATION

  def perform(instance)
    return if instance.blocked?

    Instances::ApplyVerification.call(instance, DnsAllowlist.call(instance.domain))
  end
end
