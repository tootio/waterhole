module ApplicationHelper
  SITE_NAME = "Waterhole"

  # The one-line description of the app. Also the copy under the wordmark on
  # the sign-in and About pages, and the first line of README.md -- keep them
  # in step.
  TAGLINE = "Collaborative moderation for Mastodon registration requests."

  # Past this the exact number stops changing anyone's next move, and a wider
  # badge starts pushing the navigation around on a phone.
  QUEUE_BADGE_MAX = 99

  # Views name only the page; the suffix lives here, so the browser tab and
  # the unfurled link preview can never drift apart.
  def page_title
    name = content_for(:page_title)
    name.present? ? "#{name} — #{SITE_NAME}" : SITE_NAME
  end

  def page_description
    content_for(:description).presence || TAGLINE
  end

  # Absolute, because an unfurler fetches it from somewhere else entirely.
  def share_image_url
    "#{Waterhole::Deployment.base_url}/og.png"
  end

  # Nothing waiting is worth saying with an absence, not with a "0".
  def queue_badge(count)
    return if count.zero?

    tag.span count > QUEUE_BADGE_MAX ? "#{QUEUE_BADGE_MAX}+" : count,
      class: "rounded-full bg-amber-100 dark:bg-amber-900 px-1.5 py-0.5 text-xs font-medium text-amber-900 dark:text-amber-200 tabular-nums",
      aria: { label: "#{count} awaiting review" }
  end

  def nav_class(active)
    base = "rounded px-2 py-1 "
    base + (active ? "bg-stone-900 dark:bg-stone-100 text-white dark:text-stone-900" : "text-stone-600 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800") +
      " #{ButtonHelper::FOCUS_RING}"
  end

  # From our own copy (see AvatarsController), or their initial where there is
  # none. Decorative: whatever it sits in carries the moderator's name.
  def moderator_avatar(moderator)
    shape = "size-8 shrink-0 rounded-full bg-stone-200 dark:bg-stone-700"

    if (version = moderator.avatar_version)
      image_tag avatar_path(v: version), alt: "", class: "#{shape} object-cover"
    else
      tag.span moderator.name.first.upcase, aria: { hidden: true },
        class: "#{shape} inline-flex items-center justify-center text-sm font-semibold text-stone-700 dark:text-stone-200"
    end
  end

  # Watchwords, email templates, sync history and your own herd's page all sit
  # under "My herd" in the header; every other herd's page is under "Herds".
  MY_HERD_CONTROLLERS = %w[keyword_rules email_templates sync_runs].freeze

  def my_herd_page?
    return true if controller_name.in?(MY_HERD_CONTROLLERS)

    controller_name == "instances" && action_name == "show" && @instance.present? && @instance == current_instance
  end

  # The page each legal document is served at. config/routes.rb maps the
  # slugs to paths; generating from the slug keeps that mapping in one place.
  def legal_document_path(document)
    url_for(controller: "/legal", action: :show, slug: document.slug, only_path: true)
  end

  # "the terms of service, privacy policy, and imprint", each a link.
  def legal_document_links(documents)
    to_sentence(documents.map { link_to it.title.downcase, legal_document_path(it), class: "underline" })
  end

  # A starting point for the notice an instance administrator adds to their
  # own privacy policy: applicants never see this Waterhole, so informing them
  # is the instance's job (Art. 13/14 GDPR). Written to slot into Mastodon's
  # default privacy policy (config/templates/privacy-policy.md in Mastodon),
  # after the first paragraph of "Do we disclose any information to outside
  # parties?", in its voice: "we", "you", "e-mail", "server". With signals, it
  # also covers cross-instance matching, which the terms require
  # instances to disclose.
  def applicant_notice(signals:)
    host = Waterhole::Deployment.host
    days = Waterhole::Deployment.retention.in_days.to_i
    privacy = "#{Waterhole::Deployment.base_url}#{privacy_path}"

    notice = <<~MARKDOWN
      We review applications for an account with the help of Waterhole, a
      moderation service at #{host} run by a third party. When you apply, the
      information from your registration, such as your username, your e-mail
      address, the IP address you signed up from and your reason for joining, is
      shared with it so that our moderators can review your application together.
      Waterhole deletes this information #{days} days after we have decided on
      your application. Its privacy policy is at #{privacy}.
    MARKDOWN
    return notice unless signals

    notice + <<~MARKDOWN

      To detect spam and abusive sign-ups that target several servers at once,
      Waterhole also compares your e-mail address (as a keyed hash, never in the
      clear), the network you signed up from and a fingerprint of your reason for
      joining with those of applicants to other servers that use it. Those
      servers only learn that there is a match and our server's domain, never your
      details.
    MARKDOWN
  end

  # A flash is a string or, when it needs a way on, a hash with a link. Hashes
  # survive the session cookie's JSON; an html_safe string would not stay safe.
  def flash_message(message)
    return message unless message.is_a?(Hash)

    external = message["link_url"].to_s.start_with?("https://")
    safe_join([ message["text"], " ",
      link_to(message["link_text"], message["link_url"], class: "font-medium underline",
        rel: ("noopener" if external), target: ("_blank" if external)) ])
  end

  def flash_class(type)
    case type.to_s
    when "alert" then "border-red-200 dark:border-red-900 bg-red-50 dark:bg-red-950 text-red-900 dark:text-red-200"
    when "notice" then "border-emerald-200 dark:border-emerald-900 bg-emerald-50 dark:bg-emerald-950 text-emerald-900 dark:text-emerald-200"
    else "border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-900 text-stone-700 dark:text-stone-300"
    end
  end
end
