# Sign-in is Mastodon OAuth, gated by Admission.
#
# Two gates must already be open before we will even talk to the server:
# the operator's allow/blocklist, and a DNS TXT record published by the instance
# admin. Checking them BEFORE registering an OAuth app matters -- otherwise
# anyone could make Waterhole issue requests to a host of their choosing.
class SessionsController < ApplicationController
  allow_unauthenticated_access
  # Signing in and out must work before consent; declining depends on it.
  allow_without_consent

  # The sign-in forms end in a redirect to the moderator's Mastodon server, and
  # browsers hold that redirect to form-action. Only these pages allow it.
  # Development also allows a local Mastodon on its default port, over plain http.
  content_security_policy do |policy|
    policy.form_action :self, :https, *("http://localhost:3000" if Rails.env.development?)
  end

  STATE_TTL = 10.minutes

  # Each attempt can mean a DNS lookup and requests to another server.
  throttle to: 10, within: 3.minutes, name: "sign_in", only: :create
  throttle to: 10, within: 3.minutes, name: "oauth_callback", only: :callback

  def new
    @domain = params[:domain]
    # This page makes Turbo reload it in full (see the view), so a Turbo visit
    # -- following the redirect after signing out or declining consent -- is
    # thrown away, and would take the flash with it.
    flash.keep if request.headers["X-Turbo-Request-Id"].present?
  end

  def create
    domain = Instance.new(domain: params[:domain]).domain # reuse the normalizer
    return redirect_to(new_session_path, alert: "Enter your instance's domain.") if domain.blank?

    @admission = Admission.call(domain)
    @domain = domain

    unless @admission.admitted?
      @signals = @admission.suggest_signals?(domain)
      return render :blocked, status: :forbidden
    end

    # The opt-in to being offered on the sign-in page next time, carried across
    # the round trip to Mastodon.
    session[:remember_instance] = params[:remember] == "1"

    instance = Instance.find_or_create_by!(domain: domain)
    # Before anything else is recorded: if a new install now holds the domain,
    # this wipes the old one's record, and the DNS result below belongs to it.
    Instances::ConfirmIdentity.call(instance)
    # Record what the record actually said, including which terms it accepted.
    # Going through the same transition logic as the hourly job keeps sign-in
    # from inventing a second, subtly different notion of "verified".
    Instances::ApplyVerification.call(instance, @admission.dns)

    Mastodon::OAuth.register_app(instance) unless instance.oauth_app_current?

    redirect_to Mastodon::OAuth.authorize_url(instance, state: issue_state(instance)),
      allow_other_host: true
  rescue Mastodon::InvalidResponse => e
    redirect_to new_session_path, alert: with_help("Could not reach #{domain}: #{e.message}.", "no-instance-actor")
  rescue Mastodon::Error => e
    redirect_to new_session_path, alert: with_help("Could not reach #{domain}: #{e.message}.")
  end

  def callback
    instance = verified_state_instance
    return redirect_to(new_session_path, alert: "That sign-in link has expired. Try again.") unless instance

    # Mastodon comes back with an error instead of a code when the moderator
    # declines on its authorize screen, or when it refuses the request itself.
    if params[:code].blank?
      session.delete(:remember_instance)
      return redirect_to new_session_path, alert: authorization_refused_alert(instance)
    end

    # Re-check: the gap between redirect and return is small, but a domain can be
    # blocked or lose its record inside it.
    unless Admission.call(instance.domain).admitted?
      return redirect_to new_session_path, alert: "#{instance.domain} is no longer authorised."
    end

    token = Mastodon::OAuth.exchange_code(instance, code: params[:code])
    client = Mastodon::Client.new(base_url: instance.base_url, access_token: token["access_token"])
    account = client.verify_credentials

    # Mastodon grants admin scopes to anyone who authorises the app, so the
    # role has to be checked here: nothing later re-asks before showing the queue.
    unless Mastodon::Role.can_manage_users?(account, client)
      # Someone who has lost the role loses what they already had, too.
      instance.moderators.find_by(mastodon_account_id: account["id"].to_s)&.invalidate_token!
      return redirect_to new_session_path,
        alert: "Your account on #{instance.domain} does not have the Manage Users permission, so it cannot moderate here."
    end

    # The key checked in #create is public; this checks the server holds the
    # private half before anyone is let in to what the instance has here.
    Instances::ProveIdentity.call(instance, client)

    # Read before the upsert overwrites the scopes it is decided by.
    reauthorized = instance.moderators.find_by(mastodon_account_id: account["id"].to_s)&.reauthorization_pending?
    moderator = upsert_moderator(instance, account, token)

    start_new_session_for(moderator, remember: session.delete(:remember_instance))
    redirect_to after_authentication_url, notice: signed_in_notice(moderator, reauthorized:)
  rescue Instances::ProveIdentity::Unproven => e
    # Nothing the moderator can fix, and the same words an impostor would get,
    # so the way on is the help page rather than trying again.
    redirect_to new_session_path, alert: with_help("Sign-in failed: #{e.message}. Nothing you did caused this; " \
      "an administrator of #{instance.domain} or of this Waterhole needs to look into it.", "could-not-prove")
  rescue Mastodon::Error => e
    redirect_to new_session_path, alert: with_help("Sign-in failed: #{e.message}.")
  end

  def destroy
    terminate_session
    redirect_to new_session_path, notice: "Signed out."
  end

  private

  # The first sign-in after the app was registered again leaves the old
  # authorization behind in Mastodon, holding a token Waterhole no longer uses.
  def signed_in_notice(moderator, reauthorized:)
    text = "Signed in as #{moderator.handle}."
    return text unless reauthorized

    { "text" => "#{text} Mastodon now lists Waterhole twice among your authorized apps; " \
                "Waterhole no longer uses the older entry, so you can revoke it.",
      "link_text" => "Open your authorized apps",
      "link_url" => moderator.instance.authorized_apps_url }
  end

  # A moderator away for a while meets Mastodon asking again, for search, with
  # no warning; declining because that looked wrong deserves an explanation.
  def authorization_refused_alert(instance)
    if params[:error] == "access_denied"
      with_help("You declined Waterhole's request on #{instance.domain}, so you are not signed in. " \
        "If it surprised you because you had approved Waterhole before: it asks once more because it now also " \
        "needs search permission, to check it is talking to your own server.",
        "declined", link_text: "Why it asks, and how to tell the request is genuine")
    else
      # Only an OAuth error code, never error_description: that is free text
      # from the URL, and has no business on this page.
      code = params[:error].to_s[/\A[a-z_]{1,64}\z/]
      with_help("Sign-in failed: #{instance.domain} did not authorise the sign-in#{" (#{code})" if code}.")
    end
  end

  # A flash with a link to the sign-in help page (see ApplicationHelper#flash_message).
  def with_help(text, anchor = nil, link_text: anchor ? "What can cause this" : "Sign-in help")
    { "text" => text, "link_text" => link_text, "link_url" => sign_in_help_path(anchor:) }
  end

  def upsert_moderator(instance, account, token)
    moderator = instance.moderators.find_or_initialize_by(mastodon_account_id: account["id"].to_s)
    moderator.assign_attributes(
      username: account["username"],
      display_name: account["display_name"].presence,
      avatar_url: account["avatar"].presence,
      profile_url: account["url"].presence,
      role_name: account.dig("role", "name"),
      access_token: token["access_token"],
      token_scopes: token["scope"],
      token_invalidated_at: nil,
      last_authenticated_at: Time.current
    )
    moderator.save!
    # Sync borrows a token only once its owner has consented; see Moderator#consent!.
    moderator
  end

  # Signed and expiring, with a nonce also held in the session, so a state value
  # cannot be forged, replayed, or reused after sign-in.
  def issue_state(instance)
    nonce = SecureRandom.hex(16)
    session[:oauth_nonce] = nonce
    Rails.application.message_verifier(:oauth_state)
      .generate({ instance_id: instance.id, nonce: }, expires_in: STATE_TTL)
  end

  def verified_state_instance
    payload = Rails.application.message_verifier(:oauth_state).verified(params[:state].to_s)
    return nil if payload.blank?

    # The verifier serialises with JSON, so keys come back as strings.
    expected = session.delete(:oauth_nonce)
    return nil if expected.blank? || !ActiveSupport::SecurityUtils.secure_compare(payload["nonce"].to_s, expected.to_s)

    Instance.find_by(id: payload["instance_id"])
  end
end
