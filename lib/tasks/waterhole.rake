namespace :waterhole do
  # Deliberately does not load the app: a production boot refuses to start
  # until these exist, so generating them must not need a booted app.
  desc "Print freshly generated secrets for .env.production"
  task :secrets do
    require "securerandom"

    puts <<~ENV
      # Generated #{Time.now.utc.iso8601}. Keep these safe and keep them stable:
      # losing the encryption keys makes stored tokens and emails unreadable.
      SECRET_KEY_BASE=#{SecureRandom.hex(64)}
      ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=#{SecureRandom.alphanumeric(32)}
      ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=#{SecureRandom.alphanumeric(32)}
      ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=#{SecureRandom.alphanumeric(32)}
      WATERHOLE_SHARING_HMAC_KEY=#{SecureRandom.hex(32)}
    ENV
  end

  # A stored request's match keys are only recomputed when their source changes,
  # so after EmailCanonicalizer's or ReasonFingerprint's rules change -- or
  # WATERHOLE_SHARING_HMAC_KEY, which keys both -- existing rows keep old keys
  # and silently stop matching new ones. Saving through the model refreshes
  # the cross-instance flags on both sides, under the old keys and the new.
  desc "Recompute every stored match key after the matching rules or key change"
  task rehash_match_keys: :environment do
    changed = 0
    RegistrationRequest.find_each do |request|
      if request.email.present?
        request.canonical_email_hash = EmailCanonicalizer.hash_for(request.email)
        request.email_domain = EmailCanonicalizer.domain_of(request.email)
      end
      request.invite_fingerprint = ReasonFingerprint.call(request.invite_request)
      request.signup_shape = SignupShape.call(email_domain: request.email_domain,
        username: request.username, locale: request.locale)
      next unless request.changed?

      request.save!
      request.recompute_flags! if request.pending?
      changed += 1
    end
    puts "Recomputed match keys on #{changed} #{changed == 1 ? "request" : "requests"}."
  end
end
