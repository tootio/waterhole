# Sign-in is Mastodon OAuth, gated by Admission.
#
# Two gates must already be open before we will even talk to the server:
# the operator's allow/blocklist, and a DNS TXT record published by the instance
# admin. Checking them BEFORE registering an OAuth app matters -- otherwise
# anyone could make Waterhole issue requests to a host of their choosing.
class SessionsController < ApplicationController
  allow_unauthenticated_access

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
  end

  def create
    domain = Instance.new(domain: params[:domain]).domain # reuse the normalizer
    return redirect_to(new_session_path, alert: "Enter your instance's domain.") if domain.blank?

    @admission = Admission.call(domain)
    @domain = domain

    unless @admission.admitted?
      @expected_record = DnsAllowlist.expected_record(domain)
      return render :blocked, status: :forbidden
    end

    instance = Instance.find_or_create_by!(domain: domain)
    # Record what the record actually said, including which terms it accepted.
    # Going through the same transition logic as the hourly job keeps sign-in
    # from inventing a second, subtly different notion of "verified".
    Instances::ApplyVerification.call(instance, @admission.dns)

    Mastodon::OAuth.register_app(instance) unless instance.oauth_app_current?

    redirect_to Mastodon::OAuth.authorize_url(instance, state: issue_state(instance)),
      allow_other_host: true
  rescue Mastodon::Error => e
    redirect_to new_session_path, alert: "Could not reach #{domain}: #{e.message}"
  end

  def callback
    instance = verified_state_instance
    return redirect_to(new_session_path, alert: "That sign-in link has expired. Try again.") unless instance

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

    moderator = upsert_moderator(instance, account, token)

    start_new_session_for(moderator)
    redirect_to after_authentication_url, notice: "Signed in as #{moderator.handle}."
  rescue Mastodon::Error => e
    redirect_to new_session_path, alert: "Sign-in failed: #{e.message}"
  end

  def destroy
    terminate_session
    redirect_to new_session_path, notice: "Signed out."
  end

  private

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

    # Background sync borrows a token; make sure there is one.
    instance.update!(sync_moderator: moderator) if instance.sync_moderator_id.blank?
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
