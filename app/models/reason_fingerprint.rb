# A 64-bit SimHash of an applicant's join reason, so near-identical reasons --
# the templates a signup farm fills in, whatever proxy each signup comes
# through -- can be found without comparing the texts themselves.
#
# Similar texts get fingerprints that differ in few bits. Measured on sample
# reasons: the same text, one word changed, a name swapped into a template or a
# sentence appended differ by 0-10 bits; unrelated reasons, even two generic
# "I'd like to join" lines, by 21 or more. MAX_DISTANCE sits in that gap.
#
# The three-word shingles are hashed with a key derived from the deployment's
# secret, so a fingerprint cannot be recomputed from a guessed text outside
# this Waterhole.
module ReasonFingerprint
  # Shorter reasons are too generic to mean anything when they match.
  MIN_WORDS = 8
  SHINGLE = 3
  MAX_DISTANCE = 12

  module_function

  # A signed 64-bit integer, to fit Postgres' bigint; nil for short or no text.
  def call(text)
    words = text.to_s.downcase.scan(/[\p{L}\p{N}]+/)
    return nil if words.size < MIN_WORDS

    weights = Array.new(64, 0)
    words.each_cons(SHINGLE).map { it.join(" ") }.uniq.each do |shingle|
      bits = OpenSSL::HMAC.digest("SHA256", key, shingle).unpack1("Q>")
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
