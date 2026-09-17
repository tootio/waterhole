require "test_helper"

class SmtpSettingsTest < ActiveSupport::TestCase
  SMTP_VARS = %w[SMTP_SERVER SMTP_PORT SMTP_LOGIN SMTP_PASSWORD SMTP_AUTH_METHOD SMTP_ENABLE_STARTTLS
                 SMTP_TLS SMTP_OPENSSL_VERIFY_MODE SMTP_CA_FILE SMTP_DOMAIN SMTP_FROM_ADDRESS
                 WATERHOLE_OPERATOR_EMAIL].freeze

  setup do
    @saved = ENV.to_h.slice(*SMTP_VARS)
    SMTP_VARS.each { ENV.delete(it) }
    ENV["SMTP_SERVER"] = "smtp.example.org"
  end

  teardown do
    SMTP_VARS.each { ENV.delete(it) }
    @saved.each { |k, v| ENV[k] = v }
  end

  def settings = Waterhole::Deployment.smtp_settings

  test "defaults to STARTTLS if offered on 587, verified, without auth" do
    assert_equal "smtp.example.org", settings[:address]
    assert_equal 587, settings[:port]
    assert settings[:enable_starttls_auto]
    refute settings[:enable_starttls]
    refute settings[:tls]
    assert_equal "peer", settings[:openssl_verify_mode]
    refute settings.key?(:authentication)
  end

  test "a login implies plain auth" do
    ENV["SMTP_LOGIN"] = "waterhole"
    ENV["SMTP_PASSWORD"] = "secret"

    assert_equal :plain, settings[:authentication]
    assert_equal "waterhole", settings[:user_name]
  end

  test "implicit TLS moves to 465 and turns STARTTLS off" do
    ENV["SMTP_TLS"] = "true"

    assert settings[:tls]
    assert_equal 465, settings[:port]
    refute settings[:enable_starttls_auto]
    refute settings[:enable_starttls]
  end

  test "STARTTLS can be required or disabled" do
    ENV["SMTP_ENABLE_STARTTLS"] = "always"
    assert settings[:enable_starttls]
    refute settings[:enable_starttls_auto]

    ENV["SMTP_ENABLE_STARTTLS"] = "never"
    refute settings[:enable_starttls]
    refute settings[:enable_starttls_auto]
  end

  # A typo must not quietly downgrade to sending in the clear.
  test "an unknown value stops rather than guessing" do
    ENV["SMTP_ENABLE_STARTTLS"] = "yes"
    error = assert_raises(ArgumentError) { settings }
    assert_match(/SMTP_ENABLE_STARTTLS="yes"/, error.message)
  end

  test "notifications need both a server and a recipient" do
    refute Waterhole::Deployment.operator_notifications?

    ENV["WATERHOLE_OPERATOR_EMAIL"] = "ops@example.org, second@example.org"
    assert Waterhole::Deployment.operator_notifications?
    assert_equal %w[ops@example.org second@example.org], Waterhole::Deployment.operator_emails

    ENV.delete("SMTP_SERVER")
    refute Waterhole::Deployment.operator_notifications?
  end
end
