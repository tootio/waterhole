require "test_helper"

class OperatorMailerTest < ActionMailer::TestCase
  setup do
    @saved = ENV.to_h.slice("SMTP_SERVER", "WATERHOLE_OPERATOR_EMAIL")
    ENV["SMTP_SERVER"] = "smtp.example.org"
    ENV["WATERHOLE_OPERATOR_EMAIL"] = "ops@example.org"
    @instance = instances(:gamma) # verified, not opted in, approval not given
    @instance.update_columns(signals_approved: false)
  end

  teardown do
    %w[SMTP_SERVER WATERHOLE_OPERATOR_EMAIL].each { ENV.delete(it) }
    @saved.each { |k, v| ENV[k] = v }
  end

  test "the mail names the instance and the command that approves it" do
    @instance.update_columns(verification_detail: "v=waterhole1; host=x; signals=on")
    mail = OperatorMailer.signals_requested(@instance)

    assert_equal [ "ops@example.org" ], mail.to
    assert_match "gamma.example asks to join cross-instance signals", mail.subject
    assert_match %(bin/rails "waterhole:herd:signals[gamma.example,approve]"), mail.body.to_s
    assert_match "signals=on", mail.body.to_s
  end

  test "an instance whose record starts opting in is announced once" do
    assert_enqueued_emails 1 do
      @instance.update!(signals_opted_in: true)
    end

    # The hourly re-check reads the same record again: no second mail.
    assert_no_enqueued_emails do
      @instance.update!(verification_checked_at: Time.current, signals_opted_in: true)
    end
  end

  test "an already approved instance needs nothing from the operator" do
    @instance.update_columns(signals_approved: true)

    assert_no_enqueued_emails { @instance.update!(signals_opted_in: true) }
  end

  test "an instance without access is not announced" do
    @instance.update_columns(status: "revoked")

    assert_no_enqueued_emails { @instance.update!(signals_opted_in: true) }
  end

  test "nothing is sent when mail is not configured" do
    ENV.delete("SMTP_SERVER")

    assert_no_enqueued_emails { @instance.update!(signals_opted_in: true) }
  end
end
