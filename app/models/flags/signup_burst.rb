module Flags
  # Several signups of the same shape (SignupShape: email provider, username
  # pattern, locale) within an hour, each from a different network. Rotating
  # residential proxies make every address look like a different home; the
  # batch still looks alike.
  #
  # `info`: a wave of genuine newcomers -- a platform exodus, a viral post --
  # can look like this too, so it is context for a decision, not a verdict.
  # `warning` when the burst spans other instances: an exodus picks one new
  # home per person, a farm spreads its batch to avoid any one queue noticing.
  class SignupBurst < Rule
    include Flags::CrossInstanceFlag
    include Flags::SignupPatternRule

    WINDOW = 1.hour
    MINIMUM = 5
    CAP = 100

    # Counted over the whole window, never a sample: in a burst of hundreds,
    # which rows a LIMIT happened to return would decide the severity.
    def call
      others = self.class.scope(request)
      count = others.count + 1
      return nil if count < MINIMUM

      networks = (others.distinct.pluck(:ip_group) + [ request.ip_group ]).compact.uniq.size
      return nil if networks < MINIMUM

      instances = others.where.not(instance_id: request.instance_id).joins(:instance).distinct.pluck("instances.domain")
      detect(instances.any? ? :warning : :info, count:, networks:, shape: request.signup_shape,
        window_minutes: (WINDOW / 1.minute).to_i, instances:)
    end

    # Capped: this drives the reverse fan-out, one job per row.
    def self.counterparts(request) = scope(request).limit(CAP).to_a

    # Within an hour either side of this signup.
    def self.scope(request)
      return RegistrationRequest.none if request.signup_shape.blank? || request.signed_up_at.nil?

      comparable_requests(request.instance)
        .where.not(id: request.id)
        .where(signup_shape: request.signup_shape,
          signed_up_at: (request.signed_up_at - WINDOW)..(request.signed_up_at + WINDOW))
    end
  end
end
