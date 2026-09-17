# Waterhole shows applicants' personal data and holds each moderator's Mastodon
# token, so an injected script would be worth a lot. Everything the app loads
# is its own, which lets the policy start from nothing and allow only 'self'.
#
# The two inline elements are the importmap (emitted by javascript_importmap_tags)
# and the <style> Turbo injects for its progress bar; both carry the per-request
# nonce. Turbo reads that nonce from csp_meta_tag in the layout.
#
# SessionsController loosens form-action for the sign-in forms only: signing in
# redirects the browser to the moderator's own Mastodon server, which could be
# any host.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src     :none
    policy.script_src      :self
    policy.style_src       :self
    policy.img_src         :self, :data
    policy.font_src        :self
    # 'self' covers the Action Cable websocket at the same host.
    policy.connect_src     :self
    policy.manifest_src    :self
    policy.form_action     :self
    policy.base_uri        :none
    policy.object_src      :none
    policy.frame_ancestors :none
  end

  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
  config.content_security_policy_nonce_auto = true
end
