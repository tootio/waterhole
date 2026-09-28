module Flags
  # The rules aimed at signup farms (SimilarReason, SignupBurst), which compare
  # a request with other requests' patterns rather than with a person's email
  # or network.
  module SignupPatternRule
    extend ActiveSupport::Concern

    class_methods do
      # What they compare a request with: its own instance's queue always, and
      # every participating instance's if its own participates. Symmetric, so
      # the same scope finds the requests whose flags depend on it.
      #
      # The own queue is named outright rather than trusted to be among the
      # participating ones: `participating?` reads the loaded record, the scope
      # reads the table, and while an approval is revoked or a terms grace ends
      # mid-sync the two disagree.
      def comparable_requests(instance)
        own = RegistrationRequest.where(instance_id: instance.id)
        return own unless instance.participating?

        own.or(RegistrationRequest.where(instance_id: Instance.participating.select(:id)))
      end
    end
  end
end
