# Splitting text into words for counting and comparing, at ICU's word
# boundaries: by dictionary in scripts written without spaces (Chinese,
# Japanese, Thai, Lao, Khmer, Burmese), by spaces and punctuation elsewhere.
# Pieces without a letter or digit -- spaces, punctuation -- are not words.
#
# tokens decides every stored ReasonFingerprint: after changing it, or the
# ICU version in the image, run waterhole:rehash_match_keys, or old
# fingerprints stop matching new ones.
module Words
  NO_SPACES = /[\p{Han}\p{Hiragana}\p{Katakana}\p{Thai}\p{Lao}\p{Khmer}\p{Myanmar}]/

  module_function

  # What a reader would call words: whatever stands between spaces is one,
  # so a URL or "e-mail" doesn't pad a reason, unless it's in a script
  # written without spaces.
  def count(text)
    text.to_s.split.sum do |chunk|
      if chunk.match?(NO_SPACES) then tokens(chunk).size
      elsif chunk.match?(/[\p{L}\p{N}]/) then 1
      else 0
      end
    end
  end

  def tokens(text)
    return [] if text.blank?

    # A fresh iterator each time: it holds its text, so sharing one between
    # threads would mix them up. Creating one is cheap.
    iterator = ICU::BreakIterator.new(:word, "root")
    iterator.text = text.to_s
    iterator.substrings.select { it.match?(/[\p{L}\p{N}]/) }
  end
end
