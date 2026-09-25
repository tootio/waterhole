# Verifies a request signed the way Mastodon signs its outgoing fetches: the
# draft-cavage HTTP Signatures scheme, RSA with SHA-256.
#
# Mastodon falls back to RFC 9421 only when the first attempt is answered with
# 400 or 401, so a refusal here must be something else (see
# IdentityChallengesController) and the draft is all that needs reading.
#
# Which headers are signed, and in what order, varies by release -- up to 4.5
# Accept is among them -- so the signing string is rebuilt from the `headers`
# parameter, never assumed. A proxy in front of Waterhole must therefore pass
# Host, Date and Accept through unchanged.
class HttpSignature
  # What must be signed for the signature to mean anything here: the path
  # carries the challenge, and the date keeps it from being replayed later.
  REQUIRED_HEADERS = %w[(request-target) host date].freeze
  ALGORITHMS = %w[rsa-sha256 hs2019].freeze
  MAX_CLOCK_SKEW = 1.hour

  # The Signature header's grammar, as Mastodon's SignatureParser reads it
  # (https://github.com/mastodon/mastodon/blob/e5fc481ab6685bf091b6c800b7ccff9e0e78087f/app/lib/signature_parser.rb,
  # AGPL-3.0, as is Waterhole): comma-separated key=value pairs, the value a
  # token or a quoted string.
  TOKEN = /[0-9a-zA-Z!#$%&'*+.^_`|~-]+/
  QUOTED_STRING = /"([^\\"]|(\\.))*"/
  PARAM = /(?<key>#{TOKEN})\s*=\s*((?<value>#{TOKEN})|(?<quoted_value>#{QUOTED_STRING}))/

  def self.verified?(request, public_key_pem) = new(request).verified_by?(public_key_pem)

  # The header's parameters, or nil unless the whole header parses. A duplicate
  # key is refused rather than letting one of the two win.
  def self.parse(header)
    scanner = StringScanner.new(header.to_s.delete_prefix("Signature "))
    params = {}

    while scanner.skip(PARAM)
      key = scanner[:key]
      return if params.key?(key)

      params[key] = scanner[:value] || scanner[:quoted_value][1...-1]
      scanner.skip(/\s*/)
      return params if scanner.eos?
      return unless scanner.skip(/\s*,\s*/)
    end
  end

  def initialize(request)
    @request = request
    @params = self.class.parse(request.headers["Signature"])
  end

  def verified_by?(public_key_pem)
    return false unless @params && well_formed? && date_current?

    key = OpenSSL::PKey.read(public_key_pem)
    key.verify(OpenSSL::Digest.new("SHA256"), Base64.strict_decode64(@params["signature"]), signing_string)
  rescue ArgumentError, OpenSSL::PKey::PKeyError
    false
  end

  private

  def signed_headers = @params["headers"].to_s.downcase.split

  def well_formed?
    @params["signature"].present? &&
      (@params["algorithm"].blank? || ALGORITHMS.include?(@params["algorithm"])) &&
      (REQUIRED_HEADERS - signed_headers).empty? &&
      signed_headers.all? { it == "(request-target)" || @request.headers[it].present? }
  end

  def date_current?
    (Time.httpdate(@request.headers["Date"]) - Time.current).abs <= MAX_CLOCK_SKEW
  rescue ArgumentError
    false
  end

  def signing_string
    signed_headers.map do |name|
      # original_fullpath: the path as requested, so as Mastodon signed it, even
      # were Waterhole mounted below the root.
      value = name == "(request-target)" ? "#{@request.method.downcase} #{@request.original_fullpath}" : @request.headers[name]
      "#{name}: #{value}"
    end.join("\n")
  end
end
