# Re-checks every instance's DNS authorisation. An admin removing the record is
# meant to be a real off-switch, so this runs without anyone intervening.
class VerifyInstancesJob < ApplicationJob
  queue_as :default

  def perform
    Instance.where.not(status: "blocked").find_each do |instance|
      VerifyInstanceJob.perform_later(instance)
    end
  end
end
