# Downloads a moderator's avatar so it can be served from our own origin (see
# Moderator::Avatar and AvatarsController), and the content security policy
# never has to allow images from a moderator's media host.
#
# The URL comes from the moderator's Mastodon server, so everything about it is
# distrusted: https only, every hop pinned by SsrfGuard, a size cap enforced
# while downloading, and the type decided by the file's own magic bytes rather
# than by any header. Only PNG, JPEG, GIF and WebP get through; an SVG -- the
# one image format that can carry script -- never does, whatever it claims to be.
module AvatarFetcher
  Rejected = Class.new(StandardError)

  MAX_BYTES = 1.megabyte
  # Media often sits behind a CDN or object-storage redirect or two.
  MAX_REDIRECTS = 3
  TIMEOUT = 5 # seconds

  SIGNATURES = {
    "image/png"  => ->(bytes) { bytes.start_with?("\x89PNG\r\n\x1A\n".b) },
    "image/jpeg" => ->(bytes) { bytes.start_with?("\xFF\xD8\xFF".b) },
    "image/gif"  => ->(bytes) { bytes.start_with?("GIF87a".b, "GIF89a".b) },
    "image/webp" => ->(bytes) { bytes.byteslice(0, 4) == "RIFF".b && bytes.byteslice(8, 4) == "WEBP".b }
  }.freeze

  module_function

  # Returns [bytes, content_type], or raises Rejected.
  def fetch(url)
    uri = https_uri(url)

    (MAX_REDIRECTS + 1).times do
      status, location, body = get(uri)

      case status
      when 200
        return [ body, sniff(body) || raise(Rejected, "not a PNG, JPEG, GIF or WebP image") ]
      when 301, 302, 303, 307, 308
        raise Rejected, "redirect without a location" if location.blank?
        uri = https_uri(uri.merge(location))
      else
        raise Rejected, "HTTP #{status}"
      end
    end

    raise Rejected, "more than #{MAX_REDIRECTS} redirects"
  rescue Faraday::Error, SsrfGuard::BlockedHost, URI::Error => e
    raise Rejected, e.message
  end

  def sniff(bytes)
    SIGNATURES.find { |_type, matches| matches.call(bytes) }&.first
  end

  def https_uri(url)
    uri = URI(url.to_s)
    raise Rejected, "not an https URL" unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?

    uri
  end

  # Streams the body so an oversized file is abandoned at the cap rather than
  # read to the end first.
  def get(uri)
    body = +"".b
    response = connection.get(uri.to_s) do |request|
      request.options.on_data = proc do |chunk, received|
        raise Rejected, "larger than #{MAX_BYTES} bytes" if received > MAX_BYTES

        body << chunk
      end
    end

    [ response.status, response.headers["location"], body ]
  end

  def connection
    Faraday.new do |f|
      f.headers["User-Agent"] = "Waterhole (+#{Waterhole::Deployment.base_url})"
      f.headers["Accept"] = SIGNATURES.keys.join(", ")
      f.options.open_timeout = TIMEOUT
      f.options.timeout = TIMEOUT
      # A fresh connection per hop, each pinned to an address SsrfGuard allows.
      SecureAdapter.use(f)
    end
  end
end
