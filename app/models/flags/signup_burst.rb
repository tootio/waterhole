module Flags
  # Several signups of the same shape (SignupShape: email provider, username
  # pattern, locale) within an hour, each from a different network. Rotating
  # residential proxies make every address look like a different home; the
  # batch still looks alike.
  #
  # `info`: a wave of genuine newcomers -- a platform exodus, a viral post --
  # can look like this too, so it is context for a decision, not a verdict.
  class SignupBurst < Rule
    WINDOW = 1.hour
    MINIMUM = 5

    def call
      group = self.class.counterparts(request) + [ request ]
      return nil if group.size < MINIMUM

      networks = group.filter_map(&:ip_group).uniq.size
      return nil if networks < MINIMUM

      detect(:info, count: group.size, networks:, shape: request.signup_shape,
        window_minutes: (WINDOW / 1.minute).to_i,
        instances: group.map(&:instance).reject { it.id == request.instance_id }.map(&:domain).uniq)
    end

    # Within an hour either side of this signup.
    def self.counterparts(request)
      return RegistrationRequest.none if request.signup_shape.blank? || request.signed_up_at.nil?

      Flags.comparable_requests(request.instance)
        .where.not(id: request.id)
        .where(signup_shape: request.signup_shape,
          signed_up_at: (request.signed_up_at - WINDOW)..(request.signed_up_at + WINDOW))
        .includes(:instance).limit(100).to_a
    end
  end
end
