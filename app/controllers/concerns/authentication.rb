# Session handling in the shape of Rails 8's own authentication generator --
# Current, a DB-backed Session, a signed cookie -- but the credential step is
# Mastodon OAuth rather than a password, so there is no password digest here and
# no local account to manage.
module Authentication
  extend ActiveSupport::Concern

  included do
    # Resuming is separate from requiring, and deliberately NOT skippable: the
    # public pages (legal documents, verification, sign-in) still need to know
    # who you are so the header can render signed-in. Folding this into
    # require_authentication meant allow_unauthenticated_access skipped the
    # cookie lookup too, and a signed-in moderator saw a signed-out header.
    before_action :resume_session
    before_action :require_authentication
    before_action :require_admitted_instance
    helper_method :signed_in?, :current_moderator, :current_instance
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
      skip_before_action :require_admitted_instance, **options
    end
  end

  private

  def signed_in? = Current.session.present?

  def current_moderator = Current.moderator

  def current_instance = Current.mastodon_instance

  def require_authentication
    signed_in? || request_authentication
  end

  # An instance that has been revoked or blocked since this session began stops
  # at the very next request, rather than lingering until the hourly re-check.
  def require_admitted_instance
    return unless signed_in?
    return if current_instance&.admitted?

    instance = current_instance
    reason =
      if instance&.blocked?         then "is no longer served by this Waterhole"
      elsif instance&.terms_outdated? then "has not accepted the current terms of this Waterhole"
      else "is no longer authorised"
      end

    terminate_session
    redirect_to new_session_path, alert: "#{instance&.domain} #{reason}."
  end

  def resume_session
    Current.session ||= find_session_by_cookie
  end

  # An expired session is ended here rather than merely ignored, so its row and
  # any live socket go with it.
  def find_session_by_cookie
    return nil unless (id = cookies.signed[:session_id])

    record = Session.includes(moderator: :instance).find_by(id: id)
    return nil unless record

    if record.expired?
      record.terminate!
      cookies.delete(:session_id)
      return nil
    end

    record.record_activity!
    record
  end

  def request_authentication
    # HEAD routes like GET, so remember it too rather than dropping the return_to.
    session[:return_to_after_authenticating] = request.url if request.get? || request.head?
    redirect_to new_session_path
  end

  def after_authentication_url
    session.delete(:return_to_after_authenticating) || root_url
  end

  # A fresh Rails session too, so nothing planted in the old one before sign-in
  # carries over. Only where to go next survives.
  def start_new_session_for(moderator)
    return_to = session[:return_to_after_authenticating]
    reset_session
    session[:return_to_after_authenticating] = return_to if return_to

    moderator.sessions.create!(
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    ).tap do |session|
      Current.session = session
      cookies.signed[:session_id] = { value: session.id, expires: session.expires_at, httponly: true, same_site: :lax }
      remember_recent_instance(moderator.instance.domain)
    end
  end

  def terminate_session
    Current.session&.terminate!
    Current.session = nil
    cookies.delete(:session_id)
    reset_session
  end
end
