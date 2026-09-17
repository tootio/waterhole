module Flags
  # The single strongest practical spam signal: someone who wanted in would say
  # something.
  class NoInviteRequest < Rule
    def call
      return nil if request.invite_request.present?

      detect(:warning)
    end
  end
end
