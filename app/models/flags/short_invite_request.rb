module Flags
  class ShortInviteRequest < Rule
    MIN_WORDS = 4

    def call
      text = request.invite_request
      return nil if text.blank? # NoInviteRequest covers this
      return nil if request.invite_request_words >= MIN_WORDS

      detect(:info, word_count: request.invite_request_words)
    end
  end
end
