module PushNotifications
  # A notification in Declarative Web Push form: the browser can show it without
  # running any of our code. The service worker shows the same JSON in browsers
  # that do not support that yet.
  #
  # The tag makes a newer message replace an older one of its kind rather than
  # stack up. So the body has to stand alone once it has replaced another, and
  # renotify makes a replacement alert again rather than change silently. The tag
  # holds whose it is because everyone on this deployment shares one origin, so
  # two moderators on one browser would replace each other's.
  Message = Data.define(:body, :tag, :path) do
    def self.new_registrations(count, waiting:, audience:, path:)
      noun = "registration".pluralize(count)
      body = waiting > count ? "#{count} new #{noun}, #{waiting} waiting in all" : "#{count} new #{noun} #{count == 1 ? "is" : "are"} waiting"
      new(body:, tag: "new-registrations-#{audience}", path:)
    end

    def self.forgotten_registrations(count, days:, audience:, path:)
      verb = count == 1 ? "has" : "have"
      new(body: "#{count} #{"registration".pluralize(count)} #{verb} been waiting for over #{days} #{"day".pluralize(days)}",
        tag: "forgotten-registrations-#{audience}", path:)
    end

    def self.test = new(body: "Push notifications work in this browser.", tag: "test", path: "/")

    def to_json(*)
      {
        web_push: 8030,
        notification: { title: "Waterhole", body:, tag:, renotify: true, navigate: "#{Waterhole::Deployment.base_url}#{path}" }
      }.to_json(*)
    end
  end
end
