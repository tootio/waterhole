module Mastodon
  # Resolves Mastodon's ambiguous 403 on approve/reject.
  #
  # The same status and body come back when the account is no longer pending AND
  # when the moderator's role lacks "Manage Users". The only way to tell is to
  # read the account back:
  #
  #   approved: true  -> someone approved it in Mastodon      -> conflict
  #   404             -> it was rejected (rejection deletes)  -> conflict
  #   still pending   -> the moderator genuinely lacks rights -> failed
  #   403 again       -> token lacks admin:read too           -> failed
  #
  # Never retry a 403.
  module DecisionOutcome
    Outcome = Data.define(:kind, :status, :message) do
      def conflict? = kind == :conflict
    end

    module_function

    # gone_status: what a 404 means for this request -- see
    # RegistrationRequest#deleted_upstream_status.
    def resolve(client, mastodon_account_id, gone_status: "rejected_elsewhere")
      account = client.admin_account(mastodon_account_id)

      if account["approved"]
        Outcome.new(kind: :conflict, status: "approved_elsewhere",
          message: "Already approved in Mastodon by someone else.")
      else
        Outcome.new(kind: :failed, status: nil,
          message: "Mastodon refused this action. Your moderator role may not include \"Manage Users\".")
      end
    rescue Mastodon::NotFound
      gone(gone_status)
    rescue Mastodon::Forbidden
      Outcome.new(kind: :failed, status: nil,
        message: "Mastodon refused this action and would not say why. Check your moderator role and token scopes.")
    end

    # The account no longer exists: approve/reject answered 404, or reading it
    # back did. Rejecting a pending account deletes the user, so the id 404s
    # forever -- and so does Mastodon's cleanup of accounts that never
    # confirmed. Either way someone or something else settled it: a conflict.
    def gone(gone_status)
      message = if gone_status == "expired"
        "This account no longer exists in Mastodon: its email address was never confirmed, so Mastodon removed it."
      else
        "Already rejected in Mastodon by someone else."
      end
      Outcome.new(kind: :conflict, status: gone_status, message:)
    end
  end
end
