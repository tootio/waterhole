module Flags
  class ShortInviteRequest < Rule
    MIN_WORDS = 4

    def call
      text = request.invite_request
      return nil if text.blank? # NoInviteRequest covers this
      words = request.invite_request_words
      return nil if words >= MIN_WORDS

      detect(:info, word_count: words)
    end
  end
end
