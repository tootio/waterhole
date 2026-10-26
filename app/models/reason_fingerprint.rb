# A 64-bit SimHash of an applicant's join reason, so near-identical reasons --
# the templates a signup farm fills in, whatever proxy each signup comes
# through -- can be found without comparing the texts themselves.
#
# Similar texts get fingerprints that differ in few bits, but how few depends
# on the key, so the gap is measured over 300 keys, on a template in English,
# Chinese, Japanese and Thai. A name swapped in or one word changed stays
# within MAX_DISTANCE for 87-95% of keys; unrelated reasons, even two generic
# "I'd like to join" lines, never came within it. Three-word shingles caught
# only 68-86%, and a larger MAX_DISTANCE starts to match unrelated reasons.
#
# The two-word shingles are hashed with a key derived from the deployment's
# secret, so a fingerprint cannot be recomputed from a guessed text outside
# this Waterhole.
module ReasonFingerprint
  # Shorter reasons are too generic to mean anything when they match.
  MIN_WORDS = 8
  SHINGLE = 2
  MAX_DISTANCE = 12

  module_function

  # A signed 64-bit integer, to fit Postgres' bigint; nil for short or no text.
  def call(text)
    words = Words.tokens(text.to_s.downcase)
    return nil if words.size < MIN_WORDS

    weights = Array.new(64, 0)
    secret = key
    words.each_cons(SHINGLE).map { it.join(" ") }.uniq.each do |shingle|
      bits = OpenSSL::HMAC.digest("SHA256", secret, shingle).unpack1("Q>")
      64.times { |i| weights[i] += bits[i] == 1 ? 1 : -1 }
    end

    value = weights.each_with_index.sum { |weight, i| weight.positive? ? (1 << i) : 0 }
    value >= 2**63 ? value - 2**64 : value
  end

  # Separate from the email key's own use, so the two can never collide.
  def key
    OpenSSL::HMAC.digest("SHA256", Waterhole::Deployment.sharing_hmac_key, "reason-fingerprint")
  end
end
